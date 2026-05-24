import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/auth/auth_session_host.dart';
import '../../core/auth/odoo_session_store.dart';
import '../../core/config/odoo_api_config.dart';
import '../../core/config/odoo_auth_rpc_config.dart';
import '../../core/debug/acpec_rpc_debug.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';

/// Erreur JSON-RPC (`error` dans la réponse) ou réseau.
class OdooJsonRpcException implements Exception {
  OdooJsonRpcException(this.message, {this.code, this.data});

  final String message;
  final int? code;
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

  /// Session mobile expirée / jeton refusé (réponse ACPEC ou HTTP 401).
  bool get isAuthRequired {
    if (code == 401) return true;
    final m = message.toLowerCase();
    if (m.contains('auth_required')) return true;
    if (m.contains('authentication required')) return true;
    if (m.contains('unauthorized')) return true;
    if (m.contains('session_closed')) return true;
    if (m.contains('token expired')) return true;
    if (m.contains('jwt')) return m.contains('expired') || m.contains('invalid');
    final d = data;
    if (d is Map) {
      final c = d['code']?.toString().toLowerCase() ?? '';
      if (c.contains('auth_required')) return true;
    }
    return false;
  }

  bool get requiresReLogin => isOdooSessionExpired || isAuthRequired;

  @override
  String toString() =>
      'OdooJsonRpcException($code): $message${data != null ? ' | $data' : ''}';
}

/// JSON-RPC client for ACPEC / Odoo `type='jsonrpc'` controllers.
///
/// Body: `{ "jsonrpc":"2.0", "method":"call", "params": { ... }, "id": n }` posted to a
/// full path such as `/api/acpec/mobile_auth/v1/login`.
class OdooJsonRpcClient {
  OdooJsonRpcClient({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;
  int _nextId = 1;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
        validateStatus: (s) => s != null && s < 600,
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
    throw OdooJsonRpcException('Réponse invalide : JSON objet attendu.');
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
          'Réponse vide du serveur Odoo (HTTP ${response.statusCode}). '
          'Vérifiez ODOO_JSONRPC_BASE_URL (depuis un téléphone : pas 127.0.0.1). '
          'URL : $requestUrl',
          code: response.statusCode,
        );
      }
      final lower = s.substring(0, s.length.clamp(0, 64)).toLowerCase();
      if (s.startsWith('<') ||
          lower.contains('<!doctype') ||
          lower.contains('<html')) {
        final dbHint = OdooApiConfig.databaseNameTrimmed.isEmpty
            ? ' Si Odoo est en multi-bases, ajoutez '
                '`--dart-define=ODOO_DATABASE=nom_de_la_base` '
                '(en-tête `X-Odoo-Database`).'
            : '';
        final dupApi = requestUrl.contains('/api/api/')
            ? ' L’URL contient `/api/api/` : la base '
                '`ODOO_JSONRPC_BASE_URL` ne doit pas se terminer par `/api` '
                '(seulement `http://HÔTE:8199`).'
            : '';
        throw OdooJsonRpcException(
          'Le serveur a renvoyé du HTML au lieu du JSON-RPC (route ou base URL incorrecte). '
          'Utilisez une base du type `http://HÔTE:8199` sans `/acpec/fueltoken/test` '
          'ni suffixe `/api`.'
          '$dbHint$dupApi '
          'HTTP ${response.statusCode}. URL : $requestUrl',
          code: response.statusCode,
        );
      }
      try {
        decoded = jsonDecode(s);
      } catch (_) {
        final clip = s.length > 160 ? '${s.substring(0, 160)}…' : s;
        throw OdooJsonRpcException(
          'Réponse non JSON du serveur (HTTP ${response.statusCode}) : $clip '
          '(URL : $requestUrl)',
          code: response.statusCode,
        );
      }
    }
    if (decoded is! Map) {
      throw OdooJsonRpcException(
        'Enveloppe JSON-RPC attendue (objet), reçu : ${decoded.runtimeType}. '
        'URL : $requestUrl',
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
    try {
      return await _postJsonRpcOnce(
        path: path,
        params: params,
        extraHeaders: extraHeaders,
        omitSessionHeaders: omitSessionHeaders,
      );
    } on OdooJsonRpcException catch (e) {
      if (suppressAuthRecovery ||
          omitSessionHeaders ||
          !e.requiresReLogin) {
        rethrow;
      }
      final refreshed = await _trySilentRefresh();
      if (!refreshed) {
        await OdooSessionStore.clear();
        AuthSessionHost.instance.notifySessionExpired();
        throw OdooJsonRpcException('SESSION_CLOSED', code: 401);
      }
      AcpecFueltokenRpcCoordinator.shared.clearCache();
      return postJsonRpc(
        path: path,
        params: params,
        extraHeaders: extraHeaders,
        omitSessionHeaders: omitSessionHeaders,
        suppressAuthRecovery: true,
      );
    }
  }

  Future<bool> _trySilentRefresh() async {
    final route = OdooAuthRpcConfig.refreshRoute.trim();
    if (route.isEmpty) return false;
    final refresh = await OdooSessionStore.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      await _postJsonRpcOnce(
        path: route.startsWith('/') ? route : '/$route',
        params: const <String, dynamic>{},
        extraHeaders: {'X-ACPEC-Refresh-Token': refresh},
        omitSessionHeaders: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _postJsonRpcOnce({
    required String path,
    Map<String, dynamic>? params,
    Map<String, String>? extraHeaders,
    required bool omitSessionHeaders,
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
    final cookie =
        omitSessionHeaders ? null : await OdooSessionStore.cookieHeader();
    final sid =
        omitSessionHeaders ? null : await OdooSessionStore.readSessionId();
    final bearer =
        omitSessionHeaders ? null : await OdooSessionStore.readAccessToken();
    final db = OdooApiConfig.databaseNameTrimmed;
    final cookiePresent = cookie != null && cookie.isNotEmpty;
    try {
      final headers = <String, dynamic>{
        Headers.contentTypeHeader: Headers.jsonContentType,
        Headers.acceptHeader: Headers.jsonContentType,
        if (!omitSessionHeaders && cookiePresent) 'Cookie': cookie,
        if (!omitSessionHeaders &&
            sid != null &&
            sid.isNotEmpty) 'X-Acpec-Session': sid,
        if (!omitSessionHeaders &&
            bearer != null &&
            bearer.isNotEmpty) 'Authorization': 'Bearer $bearer',
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
      if (r.statusCode == 401) {
        throw OdooJsonRpcException('AUTH_REQUIRED', code: 401);
      }
      final map = _parseJsonRpcEnvelope(r.data, r, url);
      if (map['error'] != null) {
        final err = _asJsonMap(map['error']);
        final rawCode = err['code'];
        final code = rawCode is int
            ? rawCode
            : int.tryParse(rawCode == null ? '' : '$rawCode');
        final msg = err['message']?.toString() ?? 'Erreur JSON-RPC';
        throw OdooJsonRpcException(msg, code: code, data: err['data']);
      }
      final result = map['result'];
      await OdooSessionStore.captureFromHttpResponse(r);
      await OdooSessionStore.mergeSessionFromResult(result);
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
      if (e.response?.statusCode == 401) {
        throw OdooJsonRpcException('AUTH_REQUIRED', code: 401);
      }
      final msgLower = (e.message ?? '').toLowerCase();
      if (e.type == DioExceptionType.connectionError ||
          msgLower.contains('connection refused') ||
          msgLower.contains('failed host lookup')) {
        final base = OdooApiConfig.baseUrlTrimmed;
        throw OdooJsonRpcException(
          'Serveur Odoo injoignable ($base). Vérifiez le réseau, le pare-feu, '
          'et que l’URL est joignable depuis l’appareil (pas 127.0.0.1 depuis un téléphone).',
        );
      }
      final data = e.response?.data;
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        final err = m['error'];
        if (err is Map) {
          final em = Map<String, dynamic>.from(err);
          throw OdooJsonRpcException(
            em['message']?.toString() ?? e.message ?? 'Erreur réseau',
            code: em['code'] is int ? em['code'] as int : null,
            data: em['data'],
          );
        }
      }
      throw OdooJsonRpcException(e.message ?? 'Erreur réseau');
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
