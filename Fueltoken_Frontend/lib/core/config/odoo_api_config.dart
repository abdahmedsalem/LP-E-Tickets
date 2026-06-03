/// Base HTTP(S) du serveur Odoo, sans slash final. Les chemins d’API sont absolus (`/api/acpec/...`).
class OdooApiConfig {
  OdooApiConfig._();

  /// Base HTTP(S) du serveur Odoo, **sans** slash final.
  static const String baseUrl = String.fromEnvironment(
    'ODOO_JSONRPC_BASE_URL',
    defaultValue: '',
  );

  /// Base de données Odoo lorsque plusieurs BDD sont proposées (sélecteur web).
  /// Envoie l’en-tête `X-Odoo-Database` sur les POST JSON-RPC si non vide.
  static const String databaseName = String.fromEnvironment(
    'ODOO_DATABASE',
    defaultValue: '',
  );

  /// Chemin du contrôleur JSON-RPC (sans la base). À aligner sur les routes Odoo réelles.
  static const String controllerPath = String.fromEnvironment(
    'ODOO_JSONRPC_CONTROLLER_PATH',
    defaultValue: '/acpec/fueltoken/api',
  );

  /// Origine du serveur (`scheme://host:port`) **sans aucun chemin**.
  ///
  /// Si `ODOO_JSONRPC_BASE_URL` est collée depuis la console navigateur et contient
  /// `/acpec/fueltoken/test`, ce segment est ignoré ; sinon les appels deviennent
  /// `…/acpec/fueltoken/test/api/acpec/...` → **404** et réponse HTML.
  ///
  /// Schéma : **http** ou **https** selon votre `dart-define` (ex. `https://odoo.example.com`).
  ///
  /// Corrige une erreur courante de collage : deux schémas d’affilée (`http://http://`).
  static String get baseUrlTrimmed {
    var s = baseUrl.trim();
    if (s.isEmpty) return '';

    s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');

    s = s.replaceAll(RegExp(r'/acpec/fueltoken/test/?$'), '');
    s = s.replaceAll(RegExp(r'/+$'), '');

    s = collapseDuplicateUrlSchemePrefixes(s);

    var noTrail = s.replaceAll(RegExp(r'/+$'), '');
    while (noTrail.toLowerCase().endsWith('/api')) {
      noTrail = noTrail
          .substring(0, noTrail.length - '/api'.length)
          .replaceAll(RegExp(r'/+$'), '');
    }
    s = noTrail;

    try {
      final withScheme = s.contains('://') ? s : 'http://$s';
      final u = Uri.parse(withScheme);
      if (u.hasScheme && u.host.isNotEmpty) {
        return Uri(
          scheme: u.scheme,
          host: u.host,
          port: u.hasPort ? u.port : null,
        ).toString();
      }
    } catch (_) {
      // parse impossible : repli chaîne nettoyée
    }
    return s.replaceAll(RegExp(r'/+$'), '');
  }

  /// `true` si la base pointe vers un hôte local de développement.
  ///
  /// Les appels métiers mobiles doivent viser l'instance distante configurée
  /// dans `ODOO_JSONRPC_BASE_URL`, pas `localhost` / `127.0.0.1`.
  static bool get isLocalHostBase {
    final raw = baseUrlTrimmed.trim();
    if (raw.isEmpty) return false;
    try {
      final withScheme = raw.contains('://') ? raw : 'http://$raw';
      final uri = Uri.parse(withScheme);
      final host = uri.host.toLowerCase();
      return host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '10.0.2.2' ||
          host == '::1';
    } catch (_) {
      final lower = raw.toLowerCase();
      return lower.contains('localhost') ||
          lower.contains('127.0.0.1') ||
          lower.contains('10.0.2.2') ||
          lower.contains('::1');
    }
  }

  /// Réduit `http://https://host` ou `http://http://host` à un seul préfixe
  /// `scheme://` (boucle jusqu’à 8 niveaux au cas où le collage soit répété).
  static String collapseDuplicateUrlSchemePrefixes(String raw) {
    var s = raw.trim();
    for (var i = 0; i < 8; i++) {
      final next = s.replaceFirstMapped(
        RegExp(r'^(https?://)(https?://)', caseSensitive: false),
        (m) => m.group(1)!,
      );
      if (identical(next, s) || next == s) break;
      s = next;
    }
    return s;
  }

  static String get controllerPathNormalized {
    final t = controllerPath.trim();
    if (t.isEmpty) return '';
    return t.startsWith('/') ? t : '/$t';
  }

  static bool get isConfigured => baseUrlTrimmed.isNotEmpty;

  static String get databaseNameTrimmed => databaseName.trim();
}
