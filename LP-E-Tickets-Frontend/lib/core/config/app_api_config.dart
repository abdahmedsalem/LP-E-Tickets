/// URL de base d’un service REST **legacy** éventuellement conservé pour d’autres intégrations.
///
/// Le flux de récupération de PIN n’utilise plus ce service.
class AppApiConfig {
  AppApiConfig._();

  static const String _primary = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String _legacyOtpHost = String.fromEnvironment(
    'OTP_API_BASE_URL',
    defaultValue: '',
  );

  /// Type métier transmis aux routes OTP (`Client`, etc.).
  static const String otpUserType = String.fromEnvironment(
    'OTP_USER_TYPE',
    defaultValue: 'Client',
  );

  static String get baseUrlTrimmed {
    final a = _primary.trim().replaceAll(RegExp(r'/+$'), '');
    if (a.isNotEmpty) return a;
    return _legacyOtpHost.trim().replaceAll(RegExp(r'/+$'), '');
  }

  static bool get isConfigured => baseUrlTrimmed.isNotEmpty;
}
