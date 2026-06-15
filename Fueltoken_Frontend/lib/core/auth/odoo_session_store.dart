import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<void> saveSessionId(String sessionId) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSessionId, sessionId);
  }

  static Future<String?> readSessionId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kSessionId);
  }

  static Future<void> saveAccessToken(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccessToken, token.trim());
  }

  static Future<void> saveRefreshToken(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRefreshToken, token.trim());
  }

  static Future<String?> readRefreshToken() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kRefreshToken);
    if (s == null || s.trim().isEmpty) return null;
    return s.trim();
  }

  static Future<String?> readAccessToken() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kAccessToken);
    if (s == null || s.trim().isEmpty) return null;
    return s.trim();
  }

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
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSessionId);
    await p.remove(_kAccessToken);
    await p.remove(_kRefreshToken);
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
