import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

import '../../core/auth/device_install_store.dart';
import '../../core/auth/odoo_session_store.dart';
import '../../core/config/odoo_auth_rpc_config.dart';
import '../../core/validation/contact_validators.dart';
import '../api/acpec_fueltoken_jsonrpc_api.dart';
import '../models/app_user.dart';
import 'acpec_public_api_error.dart';
import '../services/odoo_jsonrpc_client.dart' show OdooJsonRpcException;

/// Authentification ACPEC Odoo (session JSON-RPC).
class OdooAuthService {
  OdooAuthService._({AcpecFueltokenJsonRpcApi? api})
    : _api = api ?? AcpecFueltokenJsonRpcApi();

  static final OdooAuthService instance = OdooAuthService._();

  final AcpecFueltokenJsonRpcApi _api;

  Future<AppUser> login({
    required String identifier,
    required String pin,
  }) async {
    final route = OdooAuthRpcConfig.loginRoute;
    if (route.isEmpty) {
      throw StateError(
        'Login ACPEC désactivé. Définissez ODOO_USE_ACPEC_AUTH=true '
        'ou ODOO_RPC_LOGIN_METHOD=/chemin/vers/login.',
      );
    }
    try {
      await OdooSessionStore.clear();
      final idForRpc = _normalizeIdentifierForMobileAuthLogin(identifier);
      final secret = pin.trim();
      if (kDebugMode) {
        debugPrint(
          '(log appareil uniquement, pas dans la requête HTTP) login : '
          '${idForRpc.contains('@') ? 'email' : 'téléphone'} · longueurs id=${idForRpc.length} secret=${secret.length}',
        );
      }
      final result = await _api.callRoute(
        route,
        params: <String, dynamic>{
          'identifier': idForRpc,
          'secret_code': secret,
        },
      );
      final top = result is Map ? Map<String, dynamic>.from(result) : null;
      if (top != null && _acpecIndicatesFailure(top)) {
        throw AcpecPublicApiError.fromBusinessEnvelope(top).toException();
      }
      if (kDebugMode && result is Map) {
        final m = Map<String, dynamic>.from(result);
        debugPrint(
          '(log appareil) réponse login : keys=${m.keys.toList()} ok=${m['ok']}',
        );
      }
      return _userFromRpcResult(result);
    } on OdooJsonRpcException catch (e) {
      if (kDebugMode) {
        debugPrint('(log appareil) erreur réseau/JSON-RPC : ${e.message}');
      }
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('(log appareil) erreur login : $e\n$st');
      }
      rethrow;
    }
  }

  Future<void> verifySensitiveActionCode({
    required String identifier,
    required String secretCode,
  }) async {
    final route = OdooAuthRpcConfig.loginRoute;
    if (route.isEmpty) {
      throw StateError(
        'Validation de code ACPEC indisponible. Configurez ODOO_USE_ACPEC_AUTH=true.',
      );
    }
    try {
      final idForRpc = _normalizeIdentifierForMobileAuthLogin(identifier);
      final result = await _api.callRoute(
        route,
        params: <String, dynamic>{
          'identifier': idForRpc,
          'secret_code': secretCode.trim(),
        },
      );
      _ensureAcpecEnvelopeSuccess(result);
    } on OdooJsonRpcException {
      rethrow;
    }
  }
  Future<void> confirmSessionPin({required String actionCode}) async {
    final route = OdooAuthRpcConfig.confirmPinRoute;
    if (route.isEmpty) {
      throw StateError(
        'Confirmation PIN ACPEC indisponible. Configurez ODOO_USE_ACPEC_AUTH=true.',
      );
    }
    final code = actionCode.trim();
    final result = await _api.callRoute(
      route,
      params: <String, dynamic>{'action_code': code},
    );
    _ensureAcpecEnvelopeSuccess(result);
  }


  String _normalizeIdentifierForMobileAuthLogin(String raw) {
    final t = raw.trim();
    if (t.contains('@')) return t.toLowerCase();
    final local = localMrDigitsFromFull(t);
    if (kMrLocalPhoneDigits.hasMatch(local)) return local;
    return t.replaceAll(' ', '');
  }

  Future<AppUser> sessionMe() async {
    final route = OdooAuthRpcConfig.sessionRoute;
    if (route.isEmpty) {
      throw StateError(
        'Session ACPEC désactivée (ODOO_USE_ACPEC_AUTH / routes).',
      );
    }
    final sid = await OdooSessionStore.readSessionId();
    final bearer = await OdooSessionStore.readAccessToken();
    if ((sid == null || sid.isEmpty) && (bearer == null || bearer.isEmpty)) {
      throw Exception('Session absente.');
    }
    try {
      final result = await _api.callRoute(route);
      return _userFromRpcResult(result);
    } on OdooJsonRpcException {
      rethrow;
    }
  }

  /// Renouvelle la session mobile longue avec le refresh token stocké.
  ///
  /// Ne doit pas envoyer l'ancien access token : au démarrage ou après F5 web,
  /// celui-ci peut être expiré. Le refresh token est la source de vérité pour
  /// restaurer la session longue.
  Future<AppUser> refreshSession({String? refreshToken}) async {
    final route = OdooAuthRpcConfig.refreshRoute;
    if (route.isEmpty) {
      throw StateError(
        'Refresh ACPEC désactivé (ODOO_USE_ACPEC_AUTH / routes).',
      );
    }
    final refresh = (refreshToken ?? await OdooSessionStore.readRefreshToken())
        ?.trim();
    if (refresh == null || refresh.isEmpty) {
      throw Exception('Refresh token absent.');
    }
    try {
      final platform = DeviceInstallStore.currentPlatformName();
      final deviceUid = await DeviceInstallStore.readOrCreate();
      final result = await _api.callRouteWithoutSession(
        route,
        params: <String, dynamic>{
          'refresh_token': refresh,
          'device_uid': deviceUid,
          'device_name': kIsWeb ? 'Flutter Web' : 'Flutter $platform',
          'platform': platform,
          'app_version': 'dev',
        },
        extraHeaders: <String, String>{'X-ACPEC-Refresh-Token': refresh},
      );
      _ensureAcpecEnvelopeSuccess(result);
      await OdooSessionStore.mergeSessionFromResult(result);
      return _userFromRpcResult(result);
    } on OdooJsonRpcException {
      rethrow;
    }
  }

  /// Demande OTP pour la connexion mobile ACPEC.
  Future<Map<String, dynamic>> requestLoginOtp({
    required String identifier,
  }) async {
    final route = OdooAuthRpcConfig.requestOtpRoute;
    if (route.isEmpty) {
      throw StateError(
        'OTP de connexion ACPEC indisponible : configurez ODOO_USE_ACPEC_AUTH=true.',
      );
    }

    await OdooSessionStore.clear();
    try {
      final idForRpc = localMrDigitsFromFull(identifier);
      final result = await _api.callRoute(
        route,
        params: {'identifier': idForRpc, 'purpose': 'login'},
      );
      _ensureAcpecEnvelopeSuccess(result);
      final top = Map<String, dynamic>.from(result as Map);
      final data = top['data'];
      if (data is Map) {
        final dm = Map<String, dynamic>.from(data);
        top['data'] = <String, dynamic>{
          ...dm,
          'otp_challenge_id': dm['otp_challenge_id'] ?? dm['challenge_id'],
          'otp_challenge_ref': dm['otp_challenge_ref'] ?? dm['challenge_ref'],
          'otp_expires_at': dm['otp_expires_at'] ?? dm['expires_at'],
          'otp_delivery': dm['otp_delivery'] ?? dm['delivery'],
        };
      }
      return top;
    } on OdooJsonRpcException {
      rethrow;
    }
  }

  /// Vérifie l'OTP de connexion et persiste les tokens de session longue.
  Future<AppUser> verifyLoginOtp({
    required String identifier,
    required String code,
    int? challengeId,
  }) async {
    final route = OdooAuthRpcConfig.verifyOtpRoute;
    if (route.isEmpty) {
      throw StateError(
        'Vérification OTP de connexion ACPEC indisponible : configurez ODOO_USE_ACPEC_AUTH=true.',
      );
    }

    final idForRpc = localMrDigitsFromFull(identifier);
    final platform = DeviceInstallStore.currentPlatformName();
    final deviceUid = await DeviceInstallStore.readOrCreate();
    try {
      final result = await _api.callRoute(
        route,
        params: {
          if (challengeId != null && challengeId > 0)
            'challenge_id': challengeId,
          'identifier': idForRpc,
          'code': code.trim(),
          'purpose': 'login',
          'device_uid': deviceUid,
          'device_name': kIsWeb ? 'Flutter Web' : 'Flutter $platform',
          'platform': platform,
          'app_version': 'dev',
        },
      );
      _ensureAcpecEnvelopeSuccess(result);
      await OdooSessionStore.mergeSessionFromResult(result);
      return _userFromRpcResult(result);
    } on OdooJsonRpcException {
      rethrow;
    }
  }

  /// Demande d'inscription Odoo ACPEC qui déclenche un OTP SMS pour un numéro.
  Future<Map<String, dynamic>> requestSignupOtp({
    required String phoneFull,
  }) async {
    final route = OdooAuthRpcConfig.requestOtpRoute;
    if (route.isEmpty) {
      throw StateError(
        'OTP d’inscription ACPEC indisponible : définissez ODOO_JSONRPC_BASE_URL '
        '(et route request-otp par défaut `/api/acpec/mobile_auth/v1/request-otp`).',
      );
    }
    await OdooSessionStore.clear();
    try {
      final local = localMrDigitsFromFull(phoneFull);
      final result = await _api.callRoute(
        route,
        params: {'identifier': local, 'purpose': 'register'},
      );
      _ensureAcpecEnvelopeSuccess(result);
      final top = Map<String, dynamic>.from(result as Map);
      final data = top['data'];
      if (data is Map) {
        final dm = Map<String, dynamic>.from(data);
        final normalized = <String, dynamic>{
          ...dm,
          'otp_challenge_id': dm['otp_challenge_id'] ?? dm['challenge_id'],
          'otp_challenge_ref': dm['otp_challenge_ref'] ?? dm['challenge_ref'],
          'otp_expires_at': dm['otp_expires_at'] ?? dm['expires_at'],
          'otp_delivery': dm['otp_delivery'] ?? dm['delivery'],
        };
        if (dm.containsKey('dev_otp_code')) {
          normalized['otp_dev_code'] = dm['otp_dev_code'];
        }
        top['data'] = normalized;
      }
      return top;
    } on OdooJsonRpcException {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> verifySignupOtp({
    required String identifier,
    required String code,
    required String name,
    required String pin,
    required int companyId,
    int? challengeId,
  }) async {
    final route = OdooAuthRpcConfig.verifyOtpRoute;
    if (route.isEmpty) {
      throw StateError(
        'Vérification par SMS indisponible : définissez ODOO_JSONRPC_BASE_URL '
        '(et route verify par défaut `/api/acpec/mobile_auth/v1/verify-otp`).',
      );
    }
    final idForRpc = localMrDigitsFromFull(identifier);
    final platform = DeviceInstallStore.currentPlatformName();
    final deviceUid = await DeviceInstallStore.readOrCreate();
    final result = await _api.callRoute(
      route,
      params: {
        if (challengeId != null && challengeId > 0) 'challenge_id': challengeId,
        'identifier': idForRpc,
        'code': code.trim(),
        'name': name.trim(),
        'secret_code': pin,
        'company_id': companyId,
        'purpose': 'register',
        'device_uid': deviceUid,
        'device_name': kIsWeb ? 'Flutter Web' : 'Flutter $platform',
        'platform': platform,
        'app_version': 'dev',
      },
    );
    _ensureAcpecEnvelopeSuccess(result);
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> requestSignupOtpResend({
    required String identifier,
  }) async {
    final route = OdooAuthRpcConfig.requestOtpRoute;
    if (route.isEmpty) {
      throw StateError(
        'Envoi SMS indisponible : définissez ODOO_JSONRPC_BASE_URL '
        '(et route request-otp par défaut `/api/acpec/mobile_auth/v1/request-otp`).',
      );
    }
    final idForRpc = localMrDigitsFromFull(identifier);
    final result = await _api.callRoute(
      route,
      params: {'identifier': idForRpc, 'purpose': 'register'},
    );
    _ensureAcpecEnvelopeSuccess(result);
    return Map<String, dynamic>.from(result as Map);
  }

  /// Demande OTP pour la récupération de PIN via le backend ACPEC.
  Future<Map<String, dynamic>> requestPasswordResetOtp({
    required String phoneFull,
  }) async {
    final route = OdooAuthRpcConfig.requestOtpRoute;
    if (route.isEmpty) {
      throw StateError(
        'OTP de récupération ACPEC indisponible : configurez ODOO_USE_ACPEC_AUTH=true.',
      );
    }
    final idForRpc = localMrDigitsFromFull(phoneFull);
    final result = await _api.callRoute(
      route,
      params: {'identifier': idForRpc, 'purpose': 'forgot_password'},
    );
    _ensureAcpecEnvelopeSuccess(result);
    final top = Map<String, dynamic>.from(result as Map);
    final data = top['data'];
    if (data is Map) {
      final dm = Map<String, dynamic>.from(data);
      top['data'] = <String, dynamic>{
        ...dm,
        'otp_challenge_id': dm['otp_challenge_id'] ?? dm['challenge_id'],
        'otp_challenge_ref': dm['otp_challenge_ref'] ?? dm['challenge_ref'],
        'otp_expires_at': dm['otp_expires_at'] ?? dm['expires_at'],
        'otp_delivery': dm['otp_delivery'] ?? dm['delivery'],
      };
    }
    return top;
  }

  /// Vérifie l’OTP de récupération de PIN via le backend ACPEC.
  Future<Map<String, dynamic>> verifyPasswordResetOtp({
    required String identifier,
    required String code,
    required String pin,
    int? challengeId,
  }) async {
    final route = OdooAuthRpcConfig.verifyOtpRoute;
    if (route.isEmpty) {
      throw StateError(
        'Vérification OTP de récupération ACPEC indisponible : configurez ODOO_USE_ACPEC_AUTH=true.',
      );
    }
    final idForRpc = localMrDigitsFromFull(identifier);
    final platform = DeviceInstallStore.currentPlatformName();
    final deviceUid = await DeviceInstallStore.readOrCreate();
    final result = await _api.callRoute(
      route,
      params: {
        if (challengeId != null && challengeId > 0) 'challenge_id': challengeId,
        'identifier': idForRpc,
        'code': code.trim(),
        'purpose': 'forgot_password',
        'secret_code': pin.trim(),
        'device_uid': deviceUid,
        'device_name': kIsWeb ? 'Flutter Web' : 'Flutter $platform',
        'platform': platform,
        'app_version': 'dev',
      },
    );
    _ensureAcpecEnvelopeSuccess(result);
    return Map<String, dynamic>.from(result as Map);
  }

  /// Demande d’inscription ACPEC (`/api/acpec/mobile_auth/v1/signup`), sans session.
  Future<String> submitSignupRequest({
    required String name,
    required String signupIdentifier,
    required String pin,
    required int companyId,
    String note = '',
  }) async {
    final result = await submitSignupRequestDetailed(
      name: name,
      signupIdentifier: signupIdentifier,
      pin: pin,
      companyId: companyId,
      note: note,
    );
    final top = Map<String, dynamic>.from(result);
    final data = top['data'];
    if (data is Map) {
      final dm = Map<String, dynamic>.from(data);
      final msg = dm['message']?.toString();
      if (msg != null && msg.isNotEmpty && msg != 'true' && msg != 'false') {
        return msg;
      }
      final otpDelivery = dm['otp_delivery']?.toString();
      if (otpDelivery == 'configured_provider' ||
          otpDelivery == 'dev_response') {
        return 'Un code SMS a été envoyé.';
      }
    }
    return 'Compte créé. Vérifiez le code SMS pour activer votre accès.';
  }

  Future<Map<String, dynamic>> submitSignupRequestDetailed({
    required String name,
    required String signupIdentifier,
    required String pin,
    required int companyId,
    String note = '',
  }) async {
    final route = OdooAuthRpcConfig.signupRoute;
    if (route.isEmpty) {
      throw StateError(
        'Inscription ACPEC indisponible : définissez ODOO_JSONRPC_BASE_URL.',
      );
    }
    try {
      final idForRpc = localMrDigitsFromFull(signupIdentifier);
      final result = await _api.callRoute(
        route,
        params: {
          'name': name.trim(),
          'signup_identifier': idForRpc,
          'secret_code': pin,
          'company_id': companyId,
          if (note.trim().isNotEmpty) 'note': note.trim(),
        },
      );
      _ensureAcpecEnvelopeSuccess(result);
      return Map<String, dynamic>.from(result as Map);
    } on OdooJsonRpcException {
      rethrow;
    }
  }

  void _ensureAcpecEnvelopeSuccess(dynamic result) {
    if (result is! Map) {
      throw Exception('Réponse serveur invalide.');
    }
    final top = Map<String, dynamic>.from(result);
    if (_acpecIndicatesFailure(top)) {
      throw AcpecPublicApiError.fromBusinessEnvelope(top).toException();
    }
    final data = top['data'];
    if (data is Map) {
      final dm = Map<String, dynamic>.from(data);
      if (_acpecIndicatesFailure(dm)) {
        throw AcpecPublicApiError.fromBusinessEnvelope(dm).toException();
      }
    }
  }

  Future<void> logout() async {
    final route = OdooAuthRpcConfig.logoutRoute;
    try {
      if (route.isNotEmpty) {
        await _api.callRoute(route);
      }
    } on OdooJsonRpcException {
      // On efface quand même la session locale.
    } finally {
      await OdooSessionStore.clear();
    }
  }

  AppUser _userFromRpcResult(dynamic result) {
    if (result is! Map) {
      throw Exception('Réponse Odoo invalide (objet attendu).');
    }
    final top = Map<String, dynamic>.from(result);
    if (_acpecIndicatesFailure(top)) {
      throw AcpecPublicApiError.fromBusinessEnvelope(top).toException();
    }
    Map<String, dynamic> payload = top;
    final data = top['data'];
    if (data is Map) {
      payload = Map<String, dynamic>.from(data);
      if (_acpecIndicatesFailure(payload)) {
        throw AcpecPublicApiError.fromBusinessEnvelope(payload).toException();
      }
    }
    return AppUser.fromOdooProfileMap(payload, envelope: top);
  }

  /// Détecte un échec métier ACPEC (`ok`, `success`, `status`, codes HTTP textuels, …).
  static bool _acpecIndicatesFailure(Map<String, dynamic> m) {
    final ok = m['ok'];
    if (ok == false || ok == 0) return true;
    if (ok is String && ok.toLowerCase() == 'false') return true;

    final success = m['success'];
    if (success == false || success == 0) return true;
    if (success is String && success.toLowerCase() == 'false') return true;

    final st = m['status']?.toString().toLowerCase().trim();
    if (st == 'error' || st == 'failed' || st == 'failure') return true;
    if (st == 'success' || st == 'ok') return false;

    final codeRaw = m['code'];
    num? codeNum;
    if (codeRaw is num) {
      codeNum = codeRaw;
    } else if (codeRaw is String) {
      codeNum = num.tryParse(codeRaw.trim());
    }
    if (codeNum != null && codeNum != 0) {
      final explicitOk =
          m['ok'] == true ||
          m['success'] == true ||
          m['ok'] == 1 ||
          m['success'] == 1;
      if (explicitOk) {
        return false;
      }
      if (codeNum >= 200 && codeNum < 300) {
        return false;
      }
      return true;
    }
    if (codeRaw is String) {
      final c = codeRaw.toLowerCase();
      if (c.contains('error') ||
          c.contains('denied') ||
          c.contains('invalid')) {
        return true;
      }
    }

    final errVal = m['error'];
    if (errVal != null &&
        errVal is! bool &&
        m['ok'] != true &&
        m['success'] != true) {
      if (errVal is String && errVal.trim().isEmpty) {
        return false;
      }
      if (errVal is Map || errVal is String) return true;
    }

    return false;
  }
}
