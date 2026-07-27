import 'package:dio/dio.dart';

import 'secure_kv.dart';

/// Persistance du cookie de session Odoo (`session_id=…`) pour les appels JSON-RPC suivants.
///
/// Peut être renseigné depuis l’en-tête `Set-Cookie` ou depuis le corps JSON du login.
///
/// **Bearer** : certaines routes FuelToken (ex. `wallet/current`) exigent aussi
/// `Authorization: Bearer <ACCESS_TOKEN>` renvoyé au login ACPEC.
class OdooSessionStore {
  OdooSessionStore._();

  static const _kSessionId = 'ft_odoo_session_id';
  static const _kAccessToken = 'ft_odoo_access_token';
  static const _kRefreshToken = 'ft_acpec_refresh_token';

  static Future<void> saveSessionId(String sessionId) =>
      SecureKv.write(_kSessionId, sessionId);

  static Future<String?> readSessionId() =>
      SecureKv.readMigratingSharedPreference(_kSessionId);

  static Future<void> saveAccessToken(String token) =>
      SecureKv.write(_kAccessToken, token);

  static Future<void> saveRefreshToken(String token) =>
      SecureKv.write(_kRefreshToken, token);

  static Future<String?> readRefreshToken() =>
      SecureKv.readMigratingSharedPreference(_kRefreshToken);

  static Future<String?> readAccessToken() =>
      SecureKv.readMigratingSharedPreference(_kAccessToken);

  /// Valeur pour l’en-tête HTTP `Cookie`, ou `null` si pas de session stockée.
  static Future<String?> cookieHeader() async {
    final id = await readSessionId();
    if (id == null || id.isEmpty) return null;
    return 'session_id=$id';
  }

  static Future<void> captureFromHttpResponse(
    Response<dynamic> response,
  ) async {
    final list = response.headers.map['set-cookie'];
    if (list == null || list.isEmpty) return;
    for (final line in list) {
      final m = RegExp(r'session_id=([^;]+)').firstMatch(line);
      if (m != null) {
        await saveSessionId(m.group(1)!);
        return;
      }
    }
  }

  static Future<void> mergeSessionFromResult(dynamic result) async {
    if (result is! Map) return;
    final m = Map<String, dynamic>.from(result);
    var sid = m['session_id']?.toString() ?? m['sessionId']?.toString();
    if ((sid == null || sid.isEmpty) && m['data'] is Map) {
      final d = Map<String, dynamic>.from(m['data'] as Map);
      sid = d['session_id']?.toString() ?? d['sessionId']?.toString();
    }
    if (sid != null && sid.isNotEmpty) {
      await saveSessionId(sid);
    }
    await mergeAccessTokenFromResult(result);
  }

  /// Extrait `ACCESS_TOKEN` / `access_token` (niveau racine, `data`, ou `user`) après login ou RPC.
  static Future<void> mergeAccessTokenFromResult(dynamic result) async {
    if (result is! Map) return;
    final m = Map<String, dynamic>.from(result);

    String? pick(Map<String, dynamic> map) {
      for (final k in ['ACCESS_TOKEN', 'access_token', 'accessToken']) {
        final v = map[k]?.toString();
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    var tok = pick(m);
    if (tok == null && m['data'] is Map) {
      final d = Map<String, dynamic>.from(m['data'] as Map);
      tok = pick(d);
      if (tok == null && d['user'] is Map) {
        tok = pick(Map<String, dynamic>.from(d['user'] as Map));
      }
    }
    if (tok == null && m['user'] is Map) {
      tok = pick(Map<String, dynamic>.from(m['user'] as Map));
    }
    if (tok != null && tok.isNotEmpty) {
      await saveAccessToken(tok);
    }
    await mergeRefreshTokenFromResult(result);
  }

  static Future<void> clear() async {
    await SecureKv.delete(_kSessionId);
    await SecureKv.delete(_kAccessToken);
    await SecureKv.delete(_kRefreshToken);
  }

  /// Extrait `REFRESH_TOKEN` / `refresh_token` après login ou `/refresh`.
  static Future<void> mergeRefreshTokenFromResult(dynamic result) async {
    if (result is! Map) return;
    final m = Map<String, dynamic>.from(result);

    String? pick(Map<String, dynamic> map) {
      for (final k in ['REFRESH_TOKEN', 'refresh_token', 'refreshToken']) {
        final v = map[k]?.toString();
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    var tok = pick(m);
    if (tok == null && m['data'] is Map) {
      final d = Map<String, dynamic>.from(m['data'] as Map);
      tok = pick(d);
      if (tok == null && d['user'] is Map) {
        tok = pick(Map<String, dynamic>.from(d['user'] as Map));
      }
    }
    if (tok == null && m['user'] is Map) {
      tok = pick(Map<String, dynamic>.from(m['user'] as Map));
    }
    if (tok != null && tok.isNotEmpty) {
      await saveRefreshToken(tok);
    }
  }
}
