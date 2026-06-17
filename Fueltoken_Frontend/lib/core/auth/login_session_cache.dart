import 'package:shared_preferences/shared_preferences.dart';

/// Persists last successful credentials so biometric re-login works (demo app).
/// Production should use secure storage + server-issued tokens only.
class LoginSessionCache {
  LoginSessionCache._();
  static const _kId = 'ft_last_identifier';
  static const _kPin = 'ft_last_pin';
  static const _kBio = 'ft_pref_biometric';

  static bool _isUsableIdentifier(String value) {
    final s = value.trim();
    if (s.isEmpty) return false;
    final lower = s.toLowerCase();
    return lower != 'false' && lower != 'null';
  }

  static Future<void> saveLastIdentifier(String identifier) async {
    final p = await SharedPreferences.getInstance();
    final clean = identifier.trim();
    if (!_isUsableIdentifier(clean)) {
      await p.remove(_kId);
      return;
    }
    await p.setString(_kId, clean);
  }

  static Future<void> saveLastPin({
    required String identifier,
    required String pin,
  }) async {
    final p = await SharedPreferences.getInstance();
    final clean = identifier.trim();
    if (_isUsableIdentifier(clean)) {
      await p.setString(_kId, clean);
    }
    await p.setString(_kPin, pin);
  }

  static Future<String?> lastIdentifier() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kId);
    if (s == null || !_isUsableIdentifier(s)) {
      await p.remove(_kId);
      return null;
    }
    return s.trim();
  }

  static Future<String?> lastPin() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kPin);
    if (s == null || s.trim().isEmpty) return null;
    return s.trim();
  }

  static Future<bool> hasLastPin() async {
    final pin = await lastPin();
    return pin != null && pin.isNotEmpty;
  }

  static Future<bool> verifyLastPin(String pin) async {
    final stored = await lastPin();
    if (stored == null || stored.isEmpty) return false;
    return stored == pin.trim();
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kId);
    await p.remove(_kPin);
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
