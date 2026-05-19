/// Marque et périmètre société (`dart-define` en production).
class AppBrandConfig {
  AppBrandConfig._();

  /// Sous-titre sous « FuelToken » sur l’écran splash (ligne optionnelle).
  static const String operatorTagline = String.fromEnvironment(
    'APP_OPERATOR_TAGLINE',
    defaultValue: '',
  );

  /// Hint champ identifiant (login).
  static const String loginIdentifierHint = String.fromEnvironment(
    'APP_LOGIN_IDENTIFIER_HINT',
    defaultValue: '',
  );

  /// Note sous le formulaire de connexion.
  static const String loginFooterNote = String.fromEnvironment(
    'APP_LOGIN_FOOTER_NOTE',
    defaultValue: '',
  );

  /// Wordmark à côté du pictogramme (ex. nom opérateur). Vide = masqué par défaut.
  static const String orgWordmark = String.fromEnvironment(
    'APP_ORG_WORDMARK',
    defaultValue: '',
  );

  /// Slug société pour les jeux de données **démo** uniquement (mémoire).
  static const String demoCompanySlug = String.fromEnvironment(
    'DEMO_COMPANY_SLUG',
    defaultValue: 'cmp-demo',
  );

  static const String _defaultCompanyCode = String.fromEnvironment(
    'DEFAULT_COMPANY_CODE',
    defaultValue: '',
  );

  /// Valeur de repli quand le backend ne renvoie pas `company_code` (hors mode démo seed).
  static String get effectiveDefaultCompanyId {
    final raw = _defaultCompanyCode.trim();
    if (raw.isEmpty) return demoCompanySlug;
    if (raw == 'leader') return 'cmp-demo';
    return raw;
  }

  static String get resolvedLoginIdentifierHint =>
      loginIdentifierHint.isNotEmpty
          ? loginIdentifierHint
          : 'ex. contact@exemple.mr, +222 …';

  static String get resolvedLoginFooterNote =>
      loginFooterNote.isNotEmpty
          ? loginFooterNote
          : 'Utilisez l’identifiant enregistré pour votre compte FuelToken.';
}
