import 'secure_kv.dart';

/// JWT access/refresh en stockage chiffré OS.
///
/// Les anciennes valeurs SharedPreferences sont migrées une seule fois au
/// premier read, puis supprimées.
class AuthTokenStore {
  AuthTokenStore._();

  static const _kAccess = 'ft_jwt_access';
  static const _kRefresh = 'ft_jwt_refresh';

  static Future<void> save({
    required String access,
    required String refresh,
  }) async {
    await SecureKv.write(_kAccess, access);
    await SecureKv.write(_kRefresh, refresh);
  }

  static Future<String?> accessToken() =>
      SecureKv.readMigratingSharedPreference(_kAccess);

  static Future<String?> refreshToken() =>
      SecureKv.readMigratingSharedPreference(_kRefresh);

  static Future<void> clear() async {
    await SecureKv.delete(_kAccess);
    await SecureKv.delete(_kRefresh);
  }
}
