import 'package:shared_preferences/shared_preferences.dart';

/// Persists last successful credentials so biometric re-login works (demo app).
/// Production should use secure storage + server-issued tokens only.
class LoginSessionCache {
  LoginSessionCache._();
  static const _kId = 'ft_last_identifier';
  static const _kPw = 'ft_last_password';
  static const _kBio = 'ft_pref_biometric';

  static Future<void> saveLastLogin({
    required String identifier,
    required String password,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kId, identifier.trim());
    await p.setString(_kPw, password);
  }

  static Future<String?> lastIdentifier() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kId);
  }

  static Future<String?> lastPassword() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPw);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kId);
    await p.remove(_kPw);
  }

  static Future<bool> biometricPreferred() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kBio) ?? false;
  }

  static Future<void> setBiometricPreferred(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBio, v);
  }
}
