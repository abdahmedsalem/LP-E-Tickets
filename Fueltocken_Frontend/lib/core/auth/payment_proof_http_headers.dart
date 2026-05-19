import 'auth_token_store.dart';
import 'odoo_session_store.dart';

/// En-têtes HTTP pour télécharger une preuve (`/web/content/…`, URL signée, etc.).
///
/// Le login ACPEC stocke le jeton dans [OdooSessionStore] ; [AuthTokenStore] sert
/// au flux JWT REST optionnel.
Future<Map<String, String>> paymentProofHttpHeaders() async {
  final headers = <String, String>{};

  final odooBearer = await OdooSessionStore.readAccessToken();
  if (odooBearer != null && odooBearer.isNotEmpty) {
    headers['Authorization'] = 'Bearer $odooBearer';
  } else {
    final jwt = await AuthTokenStore.accessToken();
    if (jwt != null && jwt.isNotEmpty) {
      headers['Authorization'] = 'Bearer $jwt';
    }
  }

  final cookie = await OdooSessionStore.cookieHeader();
  if (cookie != null && cookie.isNotEmpty) {
    headers['Cookie'] = cookie;
  }

  return headers;
}
