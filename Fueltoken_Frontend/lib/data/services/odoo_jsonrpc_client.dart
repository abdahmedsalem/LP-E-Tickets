import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/auth/auth_session_host.dart';
import '../../core/auth/auth_token_store.dart';
import '../../core/auth/odoo_session_store.dart';
import '../../core/config/odoo_api_config.dart';
import '../../core/config/odoo_auth_rpc_config.dart';
import '../../core/debug/acpec_rpc_debug.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';

/// Erreur JSON-RPC, HTTP ou réseau.
class OdooJsonRpcException implements Exception {
  OdooJsonRpcException(
    this.message, {
    this.code,
    this.publicCode,
    this.publicAction,
    this.reference,
    this.data,
  });

  final String message;
  final int? code;

  /// Public ACPEC business error code from `result.error.code`.
  ///
  /// This is intentionally separate from JSON-RPC numeric error [code].
  final String? publicCode;

  /// Frontend action contract returned by backend (`REFRESH_REQUIRED`,
  /// `LOGOUT_REQUIRED`, etc.).
  final String? publicAction;

  /// Support reference returned by the backend (`SEC-*` / `ERR-*`).
  final String? reference;

  final Object? data;

  /// Odoo renvoie souvent `100` + libellé « Session expired ».
  bool get isOdooSessionExpired {
    if (code == 100) return true;
    final d = data;
    if (d is Map) {
      final n = d['name']?.toString().toLowerCase() ?? '';
      if (n.contains('sessionexpired')) return true;
      final msg = d['message']?.toString().toLowerCase() ?? '';
      if (msg.contains('session expired') || msg.contains('session expir')) {
        return true;
      }
    }
    final m = message.toLowerCase();
    return m.contains('session expired') ||
        m.contains('session expir') ||
        m.contains('sessionexpired') ||
        m.contains('session_expired');
  }

  String? get normalizedPublicCode {
    final value = publicCode?.trim().toUpperCase();
    return value == null || value.isEmpty ? null : value;
  }

  String? get normalizedPublicAction {
    final value = publicAction?.trim().toUpperCase();
    return value == null || value.isEmpty ? null : value;
  }

  bool get requiresRefresh {
    final action = normalizedPublicAction;
    if (action == 'REFRESH_REQUIRED') return true;
    final pc = normalizedPublicCode;
    return pc == 'SESSION_EXPIRED';
  }

  bool get requiresLogout {
    final action = normalizedPublicAction;
    if (action == 'LOGOUT_REQUIRED') return true;
    final pc = normalizedPublicCode;
    return pc == 'SESSION_CLOSED' ||
        pc == 'REFRESH_TOKEN_REQUIRED' ||
        pc == 'REFRESH_TOKEN_INVALID' ||
        pc == 'REFRESH_TOKEN_EXPIRED' ||
        pc == 'DEVICE_BLOCKED' ||
        pc == 'MOBILE_USER_BLOCKED';
  }

  /// Session mobile expirée / jeton refusé (réponse ACPEC ou HTTP 401).
  bool get isAuthRequired {
    if (requiresRefresh || requiresLogout) return true;
    if (code == 401) return true;
    final pc = normalizedPublicCode;
    if (pc != null && _isAuthBusinessCode(pc)) return true;
    final action = normalizedPublicAction;
    if (action != null && _isAuthBusinessAction(action)) return true;
    final m = message.toLowerCase();
    if (m.contains('auth_required')) return true;
    if (m.contains('authentication required')) return true;
    if (m.contains('unauthorized')) return true;
    if (m.contains('session_closed')) return true;
    if (m.contains('token expired')) return true;
    if (m.contains('jwt')) {
      return m.contains('expired') || m.contains('invalid');
    }
    final d = data;
    if (d is Map) {
      final failure = _findBusinessAuthFailure(d);
      if (failure != null) return true;
      final c = d['code']?.toString().toLowerCase() ?? '';
      if (c.contains('auth_required')) return true;
    }
    return false;
  }

  bool get requiresReLogin => isOdooSessionExpired || isAuthRequired;

  @override
  String toString() {
    final parts = <String>[
      if (code != null) 'jsonrpc=$code',
      if (publicCode != null && publicCode!.isNotEmpty) 'public=$publicCode',
      if (publicAction != null && publicAction!.isNotEmpty)
        'action=$publicAction',
      if (reference != null && reference!.isNotEmpty) 'reference=$reference',
    ];
    final suffix = parts.isEmpty ? '' : '(${parts.join(', ')})';
    return 'OdooJsonRpcException$suffix: $message';
  }
}

class _BusinessAuthFailure {
  const _BusinessAuthFailure({
    required this.code,
    required this.envelope,
    this.reference,
  });

  final String code;
  final String? reference;
  final Map<String, dynamic> envelope;
}

/// Detects ACPEC auth/session failures carried inside a JSON-RPC `result`.
///
/// Some backend routes can return HTTP 200 + JSON-RPC success while the
/// business envelope is refused (`ok: false`, `error.code: AUTH_REQUIRED`
/// or `SESSION_EXPIRED`).
/// These errors must be handled in the central JSON-RPC client, before mapper
/// or screen code can swallow them as ordinary business errors.
@visibleForTesting
OdooJsonRpcException? odooJsonRpcAuthFailureFromBusinessResult(dynamic result) {
  final failure = _findBusinessAuthFailure(result);
  if (failure == null) return null;
  return OdooJsonRpcException(
    failure.code,
    code: 401,
    publicCode: failure.code,
    publicAction: _readBusinessAction(failure.envelope),
    reference: failure.reference,
    data: failure.envelope,
  );
}

_BusinessAuthFailure? _findBusinessAuthFailure(dynamic raw) {
  if (raw is! Map) return null;
  final root = Map<String, dynamic>.from(raw);
  final rootFailure = _businessAuthFailureFromEnvelope(root);
  if (rootFailure != null) return rootFailure;

  final data = root['data'];
  if (data is Map) {
    return _businessAuthFailureFromEnvelope(Map<String, dynamic>.from(data));
  }
  return null;
}

_BusinessAuthFailure? _businessAuthFailureFromEnvelope(
  Map<String, dynamic> envelope,
) {
  if (!_looksLikeBusinessFailure(envelope)) return null;

  final error = envelope['error'];
  final errorMap = error is Map ? Map<String, dynamic>.from(error) : null;
  final code = _normalizeBusinessCode(
    errorMap?['code'] ??
        envelope['error_code'] ??
        envelope['public_code'] ??
        envelope['code'] ??
        (error is String ? error : null),
  );
  if (!_isAuthBusinessCode(code)) return null;

  final reference = _normalizeReference(
    errorMap?['reference'] ??
        errorMap?['ref'] ??
        envelope['reference'] ??
        envelope['ref'],
  );
  return _BusinessAuthFailure(
    code: code,
    reference: reference,
    envelope: envelope,
  );
}

bool _looksLikeBusinessFailure(Map<String, dynamic> envelope) {
  bool isFalseValue(dynamic value) {
    if (value == false || value == 0) return true;
    if (value is String) {
      final s = value.trim().toLowerCase();
      return s == 'false' || s == '0' || s == 'no';
    }
    return false;
  }

  final status = envelope['status']?.toString().trim().toLowerCase();
  final code = envelope['code']?.toString().trim().toLowerCase();
  final error = envelope['error'];
  return isFalseValue(envelope['ok']) ||
      isFalseValue(envelope['success']) ||
      status == 'error' ||
      status == 'failed' ||
      status == 'failure' ||
      status == 'denied' ||
      status == 'rejected' ||
      code == 'error' ||
      code == 'failed' ||
      code == 'access_denied' ||
      (error != null && error != false && error.toString().trim().isNotEmpty);
}

String _normalizeBusinessCode(dynamic value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return '';
  final lower = raw.toLowerCase();
  if (lower == 'false' || lower == 'null') return '';
  return raw.toUpperCase().replaceAll('-', '_');
}

String? _readBusinessAction(Map<String, dynamic> envelope) {
  final err = envelope['error'];
  if (err is! Map) return null;
  final raw = err['action'];
  final action = raw?.toString().trim().toUpperCase();
  return action == null || action.isEmpty ? null : action;
}

bool _isAuthBusinessCode(String code) {
  return code == 'AUTH_REQUIRED' ||
      code == 'SESSION_EXPIRED' ||
      code == 'SESSION_CLOSED' ||
      code == 'REFRESH_TOKEN_REQUIRED' ||
      code == 'REFRESH_TOKEN_INVALID' ||
      code == 'REFRESH_TOKEN_EXPIRED' ||
      code == 'DEVICE_BLOCKED' ||
      code == 'MOBILE_USER_BLOCKED';
}

bool _isAuthBusinessAction(String action) {
  return action == 'REFRESH_REQUIRED' ||
      action == 'LOGOUT_REQUIRED' ||
      action == 'LOGIN_REQUIRED';
}

String? _normalizeReference(dynamic value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  final upper = raw.toUpperCase();
  if (!upper.startsWith('SEC-') && !upper.startsWith('ERR-')) return null;
  return raw;
}

@visibleForTesting
OdooJsonRpcException? odooJsonRpcHttpFailure(int? statusCode) {
  if (statusCode == null || (statusCode >= 200 && statusCode < 300)) {
    return null;
  }

  String message;
  switch (statusCode) {
    case 400:
      message = 'La requête envoyée au serveur est invalide.';
      break;
    case 401:
      return OdooJsonRpcException('AUTH_REQUIRED', code: 401);
    case 403:
      message = 'Vous n’êtes pas autorisé à effectuer cette action.';
      break;
    case 404:
      message = 'Le service demandé est introuvable.';
      break;
    case 405:
      message = 'Cette opération n’est pas autorisée par le serveur.';
      break;
    case 408:
      message = 'Serveur momentanément indisponible. Réessayez plus tard.';
      break;
    case 413:
      message = 'La requête envoyée est trop volumineuse.';
      break;
    case 415:
      message = 'Le format de la requête n’est pas accepté par le serveur.';
      break;
    case 422:
      message = 'La requête envoyée au serveur est invalide.';
      break;
    case 429:
      message = 'Trop de requêtes. Réessayez plus tard.';
      break;
    case 500:
    case 502:
    case 503:
    case 504:
      message = 'Serveur momentanément indisponible. Réessayez plus tard.';
      break;
    default:
      message = 'Le serveur a refusé la requête (HTTP $statusCode).';
  }

  return OdooJsonRpcException(message, code: statusCode);
}

@visibleForTesting
OdooJsonRpcException odooJsonRpcExceptionFromDio(DioException error) {
  final httpFailure = odooJsonRpcHttpFailure(error.response?.statusCode);
  if (httpFailure != null) return httpFailure;

  final message = (error.message ?? '').toLowerCase();
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return OdooJsonRpcException(
        'Serveur momentanément indisponible. Réessayez plus tard.',
      );
    case DioExceptionType.connectionError:
      return OdooJsonRpcException(
        'Impossible de joindre le serveur. Vérifiez votre connexion.',
      );
    case DioExceptionType.badCertificate:
      return OdooJsonRpcException('Connexion sécurisée au serveur impossible.');
    case DioExceptionType.cancel:
      return OdooJsonRpcException('La requête a été annulée.');
    case DioExceptionType.badResponse:
      return OdooJsonRpcException(
        'Le serveur a renvoyé une réponse invalide. Réessayez.',
      );
    case DioExceptionType.unknown:
      if (message.contains('socketexception') ||
          message.contains('connection refused') ||
          message.contains('failed host lookup') ||
          message.contains('network is unreachable')) {
        return OdooJsonRpcException(
          'Impossible de joindre le serveur. Vérifiez votre connexion.',
        );
      }
      return OdooJsonRpcException('Une erreur réseau est survenue. Réessayez.');
  }
}

String _sanitizeServerMessage(
  String raw, {
  String fallback = 'Une erreur est survenue. Réessayez.',
}) {
  var msg = raw.trim();
  if (msg.isEmpty) return fallback;

  final lower = msg.toLowerCase();
  if (lower.contains('<html') ||
      lower.contains('<!doctype') ||
      (lower.contains('json') && lower.contains('unexpected character')) ||
      lower.contains('formatexception') ||
      (lower.contains('json') && lower.contains('html'))) {
    return 'Le serveur a renvoyé une réponse invalide. Réessayez.';
  }
  if (lower.contains('socketexception') ||
      lower.contains('connection refused') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable')) {
    return 'Impossible de joindre le serveur. Vérifiez votre connexion.';
  }

  msg = msg
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (msg.isEmpty) return fallback;
  if (msg.length > 200) return '${msg.substring(0, 200)}…';
  return msg;
}

enum _SilentRefreshStatus { refreshed, terminalFailure, transientFailure }

class _SilentRefreshResult {
  const _SilentRefreshResult._(this.status, [this.error]);

  const _SilentRefreshResult.refreshed()
    : this._(_SilentRefreshStatus.refreshed);

  const _SilentRefreshResult.terminal([OdooJsonRpcException? error])
    : this._(_SilentRefreshStatus.terminalFailure, error);

  const _SilentRefreshResult.transient([OdooJsonRpcException? error])
    : this._(_SilentRefreshStatus.transientFailure, error);

  final _SilentRefreshStatus status;
  final OdooJsonRpcException? error;

  bool get refreshed => status == _SilentRefreshStatus.refreshed;
  bool get terminalFailure => status == _SilentRefreshStatus.terminalFailure;
}

/// JSON-RPC client for ACPEC / Odoo `type='jsonrpc'` controllers.
///
/// Body: `{ "jsonrpc":"2.0", "method":"call", "params": { ... }, "id": n }` posted to a
/// full path such as `/api/acpec/mobile_auth/v1/login`.
class OdooJsonRpcClient {
  OdooJsonRpcClient({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;
  int _nextId = 1;

  Future<_SilentRefreshResult>? _refreshInFlight;
  Future<void>? _logoutCleanupInFlight;
  bool _terminalLogoutInProgress = false;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
        validateStatus: (s) => s != null && s >= 200 && s < 300,
        headers: {
          Headers.contentTypeHeader: Headers.jsonContentType,
          Headers.acceptHeader: Headers.jsonContentType,
        },
      ),
    );
  }

  void _ensureConfigured() {
    if (!OdooApiConfig.isConfigured) {
      throw OdooJsonRpcException(
        'Définissez ODOO_JSONRPC_BASE_URL, ex. : '
        'flutter run --dart-define=ODOO_JSONRPC_BASE_URL=http://serveur:8199',
      );
    }
  }

  Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw OdooJsonRpcException(
      'Le serveur a renvoyé une réponse invalide. Réessayez.',
    );
  }

  /// Corps de réponse HTTP → enveloppe JSON-RPC `{ "jsonrpc", "result"|"error", "id" }`.
  Map<String, dynamic> _parseJsonRpcEnvelope(
    dynamic data,
    Response<dynamic> response,
    String requestUrl,
  ) {
    dynamic decoded = data;
    if (data is String) {
      final s = data.trim();
      if (s.isEmpty) {
        throw OdooJsonRpcException(
          'Le serveur a renvoyé une réponse vide. Vérifiez l’URL ou réessayez.',
          code: response.statusCode,
        );
      }
      final lower = s.substring(0, s.length.clamp(0, 64)).toLowerCase();
      if (s.startsWith('<') ||
          lower.contains('<!doctype') ||
          lower.contains('<html')) {
        throw OdooJsonRpcException(
          'Le serveur a renvoyé une page HTML au lieu d’une réponse API. Vérifiez l’URL.',
          code: response.statusCode,
        );
      }
      try {
        decoded = jsonDecode(s);
      } catch (_) {
        throw OdooJsonRpcException(
          'Le serveur a renvoyé une réponse non JSON. Réessayez.',
          code: response.statusCode,
        );
      }
    }
    if (decoded is! Map) {
      throw OdooJsonRpcException(
        'Le serveur a renvoyé une structure invalide. Réessayez.',
        code: response.statusCode,
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Envoie une requête JSON-RPC avec `method: "call"` vers [path] (commence par `/`).
  ///
  /// Après chaque réponse JSON-RPC réussie, la session stockée est mise à jour depuis
  /// `Set-Cookie` et/ou le champ `session_id` dans [result].
  ///
  /// Si [omitSessionHeaders] est vrai : pas de Cookie / `X-Acpec-Session` / `Authorization`
  /// (ex. route `/refresh` avec `X-ACPEC-Refresh-Token` uniquement).
  ///
  /// Une tentative de [OdooAuthRpcConfig.refreshRoute] est faite une fois si la réponse
  /// indique une session expirée et qu’un refresh token est stocké.
  Future<dynamic> postJsonRpc({
    required String path,
    Map<String, dynamic>? params,
    Map<String, String>? extraHeaders,
    bool omitSessionHeaders = false,
    bool suppressAuthRecovery = false,
  }) async {
    final sessionIdUsedAtSend = omitSessionHeaders
        ? null
        : await OdooSessionStore.readSessionId();
    final accessTokenUsedAtSend = omitSessionHeaders
        ? null
        : await OdooSessionStore.readAccessToken();
    try {
      return await _postJsonRpcOnce(
        path: path,
        params: params,
        extraHeaders: extraHeaders,
        omitSessionHeaders: omitSessionHeaders,
        sessionIdOverride: sessionIdUsedAtSend,
        accessTokenOverride: accessTokenUsedAtSend,
      );
    } on OdooJsonRpcException catch (e) {
      if (suppressAuthRecovery || omitSessionHeaders) {
        rethrow;
      }
      if (e.requiresLogout) {
        await _clearLocalAuthAndNotify();
        throw OdooJsonRpcException(
          e.publicCode ?? 'SESSION_CLOSED',
          code: 401,
          publicCode: e.publicCode ?? 'SESSION_CLOSED',
          publicAction: e.publicAction ?? 'LOGOUT_REQUIRED',
          reference: e.reference,
          data: e.data,
        );
      }
      if (!e.requiresReLogin) {
        rethrow;
      }

      final staleSession = await _hasSessionChangedSinceRequest(
        previousSessionId: sessionIdUsedAtSend,
        previousAccessToken: accessTokenUsedAtSend,
      );
      if (staleSession) {
        AcpecFueltokenRpcCoordinator.shared.clearCache();
        return postJsonRpc(
          path: path,
          params: params,
          extraHeaders: extraHeaders,
          omitSessionHeaders: omitSessionHeaders,
          suppressAuthRecovery: true,
        );
      }

      final refresh = await _refreshSingleFlight();
      if (refresh.refreshed) {
        AcpecFueltokenRpcCoordinator.shared.clearCache();
        return postJsonRpc(
          path: path,
          params: params,
          extraHeaders: extraHeaders,
          omitSessionHeaders: omitSessionHeaders,
          suppressAuthRecovery: true,
        );
      }
      if (refresh.terminalFailure) {
        final terminalError = refresh.error;
        await _clearLocalAuthAndNotify();
        throw OdooJsonRpcException(
          terminalError?.publicCode ?? 'SESSION_CLOSED',
          code: 401,
          publicCode: terminalError?.publicCode ?? 'SESSION_CLOSED',
          publicAction: terminalError?.publicAction ?? 'LOGOUT_REQUIRED',
          reference: terminalError?.reference ?? e.reference,
          data: terminalError?.data ?? e.data,
        );
      }

      // Erreur transitoire pendant /refresh : réseau, timeout, SERVER_ERROR.
      // On garde la session locale et on remonte l'erreur au caller.
      throw refresh.error ?? e;
    }
  }

  Future<void> _clearLocalAuthAndNotify() {
    _terminalLogoutInProgress = true;
    final inFlight = _logoutCleanupInFlight;
    if (inFlight != null) return inFlight;
    final cleanup = () async {
      await OdooSessionStore.clear();
      await AuthTokenStore.clear();
      AuthSessionHost.instance.notifySessionExpired();
    }();
    _logoutCleanupInFlight = cleanup;
    return cleanup;
  }

  bool _tokenChanged(String? previous, String? current) {
    final p = previous?.trim();
    final c = current?.trim();
    return p != null && p.isNotEmpty && c != null && c.isNotEmpty && p != c;
  }

  Future<bool> _hasSessionChangedSinceRequest({
    String? previousSessionId,
    String? previousAccessToken,
  }) async {
    final currentSessionId = await OdooSessionStore.readSessionId();
    final currentAccessToken = await OdooSessionStore.readAccessToken();
    return _tokenChanged(previousSessionId, currentSessionId) ||
        _tokenChanged(previousAccessToken, currentAccessToken);
  }

  Future<_SilentRefreshResult> _refreshSingleFlight() {
    if (_terminalLogoutInProgress) {
      return Future<_SilentRefreshResult>.value(
        _SilentRefreshResult.terminal(
          OdooJsonRpcException(
            'SESSION_CLOSED',
            code: 401,
            publicCode: 'SESSION_CLOSED',
            publicAction: 'LOGOUT_REQUIRED',
          ),
        ),
      );
    }
    final current = _refreshInFlight;
    if (current != null) return current;

    late final Future<_SilentRefreshResult> tracked;
    tracked = _trySilentRefresh().whenComplete(() {
      if (identical(_refreshInFlight, tracked)) {
        _refreshInFlight = null;
      }
    });
    _refreshInFlight = tracked;
    return tracked;
  }

  Future<_SilentRefreshResult> _trySilentRefresh() async {
    final route = OdooAuthRpcConfig.refreshRoute.trim();
    if (route.isEmpty) {
      return _SilentRefreshResult.terminal(
        OdooJsonRpcException('REFRESH_TOKEN_REQUIRED', code: 401),
      );
    }
    final refresh = await OdooSessionStore.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      return _SilentRefreshResult.terminal(
        OdooJsonRpcException('REFRESH_TOKEN_REQUIRED', code: 401),
      );
    }

    final previousSessionId = await OdooSessionStore.readSessionId();
    final previousAccessToken = await OdooSessionStore.readAccessToken();

    try {
      final result = await _postJsonRpcOnce(
        path: route.startsWith('/') ? route : '/$route',
        params: const <String, dynamic>{},
        extraHeaders: {'X-ACPEC-Refresh-Token': refresh},
        omitSessionHeaders: true,
      );

      final authFailure = odooJsonRpcAuthFailureFromBusinessResult(result);
      if (authFailure != null) {
        return _SilentRefreshResult.terminal(authFailure);
      }

      final nextSessionId = await OdooSessionStore.readSessionId();
      final nextAccessToken = await OdooSessionStore.readAccessToken();

      final sessionRotated =
          nextSessionId != null &&
          nextSessionId.isNotEmpty &&
          nextSessionId != previousSessionId;
      final accessRotated =
          nextAccessToken != null &&
          nextAccessToken.isNotEmpty &&
          nextAccessToken != previousAccessToken;

      if (sessionRotated || accessRotated) {
        return const _SilentRefreshResult.refreshed();
      }
      return _SilentRefreshResult.terminal(
        OdooJsonRpcException('SESSION_CLOSED', code: 401),
      );
    } on OdooJsonRpcException catch (e) {
      if (e.requiresLogout || e.isAuthRequired || e.isOdooSessionExpired) {
        return _SilentRefreshResult.terminal(e);
      }
      return _SilentRefreshResult.transient(e);
    } catch (_) {
      return _SilentRefreshResult.transient(
        OdooJsonRpcException(
          'Impossible de joindre le serveur. Vérifiez votre connexion.',
        ),
      );
    }
  }

  Future<dynamic> _postJsonRpcOnce({
    required String path,
    Map<String, dynamic>? params,
    Map<String, String>? extraHeaders,
    required bool omitSessionHeaders,
    String? sessionIdOverride,
    String? accessTokenOverride,
  }) async {
    _ensureConfigured();
    final url = _join(OdooApiConfig.baseUrlTrimmed, path);
    final id = _nextId++;
    final body = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'call',
      'params': params ?? <String, dynamic>{},
      'id': id,
    };
    final cookie = omitSessionHeaders
        ? null
        : await OdooSessionStore.cookieHeader();
    final sid = omitSessionHeaders
        ? null
        : (sessionIdOverride ?? await OdooSessionStore.readSessionId());
    final bearer = omitSessionHeaders
        ? null
        : (accessTokenOverride ?? await OdooSessionStore.readAccessToken());
    final db = OdooApiConfig.databaseNameTrimmed;
    final cookiePresent = cookie != null && cookie.isNotEmpty;
    try {
      final headers = <String, dynamic>{
        Headers.contentTypeHeader: Headers.jsonContentType,
        Headers.acceptHeader: Headers.jsonContentType,
        if (!omitSessionHeaders && cookiePresent) 'Cookie': cookie,
        if (!omitSessionHeaders && sid != null && sid.isNotEmpty)
          'X-Acpec-Session': sid,
        if (!omitSessionHeaders && bearer != null && bearer.isNotEmpty)
          'Authorization': 'Bearer $bearer',
        if (db.isNotEmpty) 'X-Odoo-Database': db,
        ...?extraHeaders,
      };
      final r = await _dio.post<dynamic>(
        url,
        data: body,
        options: Options(headers: headers),
      );
      AcpecRpcDebug.logRoundTrip(
        httpPath: path,
        fullUrl: url,
        jsonRpcEnvelope: Map<String, dynamic>.from(body),
        cookiePresent: cookiePresent,
        xOdooDatabase: db.isEmpty ? null : db,
        httpStatus: r.statusCode,
        responseBody: r.data,
      );
      final httpFailure = odooJsonRpcHttpFailure(r.statusCode);
      if (httpFailure != null) throw httpFailure;
      final map = _parseJsonRpcEnvelope(r.data, r, url);
      if (map['error'] != null) {
        final err = _asJsonMap(map['error']);
        final rawCode = err['code'];
        final code = rawCode is int
            ? rawCode
            : int.tryParse(rawCode == null ? '' : '$rawCode');
        final msg = _sanitizeServerMessage(
          err['message']?.toString() ?? 'Erreur serveur.',
        );
        throw OdooJsonRpcException(msg, code: code, data: err['data']);
      }
      final result = map['result'];
      final authFailure = odooJsonRpcAuthFailureFromBusinessResult(result);
      if (authFailure != null) {
        throw authFailure;
      }
      await OdooSessionStore.captureFromHttpResponse(r);
      await OdooSessionStore.mergeSessionFromResult(result);
      _terminalLogoutInProgress = false;
      _logoutCleanupInFlight = null;
      return result;
    } on OdooJsonRpcException {
      rethrow;
    } on DioException catch (e) {
      if (AcpecRpcDebug.enabled) {
        AcpecRpcDebug.logRoundTrip(
          httpPath: path,
          fullUrl: url,
          jsonRpcEnvelope: Map<String, dynamic>.from(body),
          cookiePresent: cookiePresent,
          xOdooDatabase: db.isEmpty ? null : db,
          httpStatus: e.response?.statusCode,
          responseBody: e.response?.data,
          note: 'Dio: ${e.type} ${e.message}',
        );
      }
      throw odooJsonRpcExceptionFromDio(e);
    }
  }

  static String _join(String base, String path) {
    if (path.isEmpty) return base;
    var b = base.trim().replaceAll(RegExp(r'/+$'), '');
    var p = path.trim();
    if (!p.startsWith('/')) {
      p = '/$p';
    }
    // Si ODOO_JSONRPC_BASE_URL se termine par `/api`, les routes absolues `/api/acpec/...`
    // donneraient une double portion `/api/api/…` → 404 HTML Odoo typique.
    while (b.toLowerCase().endsWith('/api') &&
        p.toLowerCase().startsWith('/api')) {
      b = b
          .substring(0, b.length - '/api'.length)
          .replaceAll(RegExp(r'/+$'), '');
    }
    // Résolution d’URL stricte (évite toute concat ambiguë) : uniquement origine + chemin absolu.
    try {
      final withScheme = b.contains('://') ? b : 'http://$b';
      final origin = Uri.parse(withScheme);
      if (origin.hasScheme && origin.host.isNotEmpty) {
        return origin.resolve(p).toString();
      }
    } catch (_) {}
    return '$b$p';
  }
}
