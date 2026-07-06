import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stockage clé/valeur chiffré par l'OS (Keystore Android / Keychain iOS).
///
/// Une clé illisible est traitée comme absente : l'utilisateur repasse par
/// l'OTP. Il n'y a jamais de repli durable vers SharedPreferences pour les
/// secrets.
class SecureKv {
  SecureKv._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<bool> _tryWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return true;
    } catch (_) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return false;
    }
  }

  static Future<void> write(String key, String value) async {
    final clean = value.trim();
    if (clean.isEmpty) {
      await delete(key);
      return;
    }
    await _tryWrite(key, clean);
  }

  static Future<String?> read(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  /// Migration one-shot depuis l'ancien SharedPreferences.
  ///
  /// Si la migration vers SecureStorage échoue, l'ancienne valeur claire est
  /// supprimée et on renvoie null : re-login OTP plutôt que réutilisation d'un
  /// secret en clair.
  static Future<String?> readMigratingSharedPreference(String key) async {
    final secureValue = await read(key);
    if (secureValue != null) return secureValue;

    final prefs = await SharedPreferences.getInstance();
    final legacyValue = prefs.getString(key);
    if (legacyValue == null || legacyValue.trim().isEmpty) {
      await prefs.remove(key);
      return null;
    }

    final clean = legacyValue.trim();
    final migrated = await _tryWrite(key, clean);
    await prefs.remove(key);
    return migrated ? clean : null;
  }

  static Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}

    // Nettoyage compat : supprime aussi l'ancienne valeur SharedPreferences si
    // elle existe encore après une mise à jour depuis une ancienne version.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}
