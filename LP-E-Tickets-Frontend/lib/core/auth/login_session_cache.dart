import 'package:shared_preferences/shared_preferences.dart';

/// Persists only non-secret login UX preferences.
/// PIN values are never stored here; server confirm-pin is the only unlock authority.
class LoginSessionCache {
  LoginSessionCache._();
  static const _kId = 'ft_last_identifier';
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


  static Future<String?> lastIdentifier() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kId);
    if (s == null || !_isUsableIdentifier(s)) {
      await p.remove(_kId);
      return null;
    }
    return s.trim();
  }




  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kId);
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
