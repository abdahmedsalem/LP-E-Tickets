import 'package:shared_preferences/shared_preferences.dart';

/// Stockage simple des JWT (access / refresh) après login ou inscription API.
///
/// **Production :** migrer vers `flutter_secure_storage` ou le trousseau plateforme.
class AuthTokenStore {
  AuthTokenStore._();

  static const _kAccess = 'ft_jwt_access';
  static const _kRefresh = 'ft_jwt_refresh';

  static Future<void> save({
    required String access,
    required String refresh,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccess, access);
    await p.setString(_kRefresh, refresh);
  }

  static Future<String?> accessToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kAccess);
  }

  static Future<String?> refreshToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kRefresh);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kAccess);
    await p.remove(_kRefresh);
  }
}
