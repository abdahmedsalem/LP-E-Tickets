import 'package:dio/dio.dart';

import '../../core/config/app_api_config.dart';
import '../../core/validation/contact_validators.dart';
import '../models/app_user.dart';

/// Canaux pour l’envoi OTP (inscription / récupération).
enum OtpChannel { email, sms }

/// Client HTTP pour l’OTP et l’inscription (service REST externe, optionnel).
///
/// Routes attendues sous [AppApiConfig] : `register-otp-email`, `register-otp-sms`, …
///
/// Définir `--dart-define=API_BASE_URL=https://...` (ou `OTP_API_BASE_URL`).
/// Optionnel : `--dart-define=OTP_USER_TYPE=Client`.
class OtpRemoteService {
  OtpRemoteService({Dio? dio}) : _dioOverride = dio;

  final Dio? _dioOverride;
  Dio? _cachedDio;

  /// Sans [dio] injecté : instance créée à la première requête, après contrôle de config.
  Dio get _dio {
    final overridden = _dioOverride;
    if (overridden != null) return overridden;
    _ensureConfigured();
    _cachedDio ??= Dio(
      BaseOptions(
        baseUrl: AppApiConfig.baseUrlTrimmed,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        validateStatus: (s) => s != null && s < 600,
        headers: {
          Headers.contentTypeHeader: Headers.jsonContentType,
          Headers.acceptHeader: Headers.jsonContentType,
        },
      ),
    );
    return _cachedDio!;
  }

  void _ensureConfigured() {
    if (!AppApiConfig.isConfigured) {
      throw OtpException(
        'Définissez API_BASE_URL ou OTP_API_BASE_URL — '
        'ex. : flutter run --dart-define=API_BASE_URL=https://api.example.com',
      );
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw OtpException('Réponse serveur invalide (JSON attendu).');
  }

  /// Réponses : `success: true` ou `status: 'success'`.
  void _ensureSuccess(Map<String, dynamic> d) {
    final ok = d['success'] == true || d['status']?.toString() == 'success';
    if (ok) return;
    final msg = d['message']?.toString() ?? 'Erreur API';
    throw OtpException(msg);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    _ensureConfigured();
    try {
      final r = await _dio.post<dynamic>(path, data: body);
      final d = _asMap(r.data);
      if (r.statusCode != null && r.statusCode! >= 400) {
        final msg = d['message']?.toString() ?? 'Erreur HTTP ${r.statusCode}';
        throw OtpException(msg);
      }
      _ensureSuccess(d);
      return d;
    } on OtpException {
      rethrow;
    } on DioException catch (e) {
      throw _otpExceptionFromDio(e);
    }
  }

  OtpException _otpExceptionFromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final msg = m['message']?.toString();
      if (msg != null && msg.isNotEmpty) return OtpException(msg);
    }
    final base = AppApiConfig.baseUrlTrimmed;
    final msgLower = (e.message ?? '').toLowerCase();
    if (e.type == DioExceptionType.connectionError ||
        msgLower.contains('connection refused') ||
        msgLower.contains('failed host lookup')) {
      return OtpException(
        'Service REST injoignable ($base). Vérifiez l’URL, le réseau et que '
        'le serveur accepte les requêtes depuis cet appareil (LAN, HTTPS, pare-feu).',
      );
    }
    return OtpException(e.message ?? 'Erreur réseau');
  }

  /// `register_otp_email` — champs : email, user_type, full_name, birth_date (optionnel).
  Future<void> sendRegistrationOtpEmail({
    required String email,
    required String name,
  }) async {
    await _post('/api/register-otp-email/', {
      'email': email.trim(),
      'user_type': AppApiConfig.otpUserType,
      'full_name': name.trim(),
      'birth_date': null,
    });
  }

  /// `register_otp_sms` — champs : phone, user_type, full_name, birth_date (optionnel).
  Future<void> sendRegistrationOtpSms({
    required String phoneFull,
    required String name,
  }) async {
    await _post('/api/register-otp-sms/', {
      'phone': phoneFull.trim(),
      'user_type': AppApiConfig.otpUserType,
      'full_name': name.trim(),
      'birth_date': null,
    });
  }

  Future<void> sendRegistrationOtp({
    required OtpChannel channel,
    required String email,
    required String name,
    required String phoneFull,
  }) async {
    if (channel == OtpChannel.email) {
      await sendRegistrationOtpEmail(email: email, name: name);
    } else {
      await sendRegistrationOtpSms(phoneFull: phoneFull, name: name);
    }
  }

  /// `send_otp_email` — compte existant : email, user_type.
  Future<void> sendForgotOtpEmail({required String email}) async {
    await _post('/api/send-otp-email/', {
      'email': email.trim(),
      'user_type': AppApiConfig.otpUserType,
    });
  }

  /// `send_otp_sms` — compte existant : phone, user_type.
  Future<void> sendForgotOtpSms({required String phoneFull}) async {
    await _post('/api/send-otp-sms/', {
      'phone': phoneFull.trim(),
      'user_type': AppApiConfig.otpUserType,
    });
  }

  Future<void> sendForgotOtp({
    required OtpChannel channel,
    required String identifier,
  }) async {
    if (channel == OtpChannel.email) {
      await sendForgotOtpEmail(email: identifier.trim());
    } else {
      await sendForgotOtpSms(phoneFull: identifier.trim());
    }
  }

  static void _validateOtpCodeLength(String clean) {
    if (clean.length < 4 || clean.length > 6) {
      throw OtpException(
        'Le code doit avoir 4 à 6 chiffres (email : 4, SMS : 6).',
      );
    }
  }

  /// `verify_otp` — identifier (email ou +222…), otp_code ; `user_type` optionnel.
  Future<Map<String, dynamic>> verifyOtp({
    required String identifier,
    required String code,
  }) async {
    final clean = code.trim().replaceAll(RegExp(r'\D'), '');
    _validateOtpCodeLength(clean);

    return _post('/api/verify-otp/', {
      'identifier': identifier.trim(),
      'otp_code': clean,
      'user_type': AppApiConfig.otpUserType,
    });
  }

  /// Extrait le profil depuis la réponse `complete_registration` (clé `user`).
  AppUser userFromCompleteRegistration(Map<String, dynamic> d) {
    final u = d['user'];
    if (u is! Map) {
      throw OtpException(
        'Réponse inscription : champ « user » manquant ou invalide.',
      );
    }
    return AppUser.fromOtpApiUserJson(Map<String, dynamic>.from(u));
  }

  /// `complete_registration` — après OTP vérifié (JSON uniquement, sans fichier).
  Future<Map<String, dynamic>> completeRegistration({
    required String email,
    required String phoneFull,
    required String password,
    required String fullName,
  }) async {
    final localPhone = localMrDigitsFromFull(phoneFull);
    return _post('/api/complete-registration/', {
      'email': email.trim(),
      'phone': localPhone,
      'password': password,
      'user_type': AppApiConfig.otpUserType,
      'full_name': fullName.trim(),
    });
  }

  /// `reset_password` — identifier, code (OTP), new_password (voir `views.reset_password`).
  Future<void> resetPassword({
    required String identifier,
    required String otpCode,
    required String newPassword,
  }) async {
    final clean = otpCode.trim().replaceAll(RegExp(r'\D'), '');
    _validateOtpCodeLength(clean);
    await _post('/api/reset-password/', {
      'identifier': identifier.trim(),
      'code': clean,
      'new_password': newPassword,
    });
  }
}

class OtpException implements Exception {
  OtpException(this.message);
  final String message;
  @override
  String toString() => message;
}
