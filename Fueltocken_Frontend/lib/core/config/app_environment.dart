import 'package:flutter/foundation.dart';

import 'app_api_config.dart';
import 'app_brand_config.dart';
import 'odoo_api_config.dart';

import '../../data/models/app_user.dart';

/// Règles d’exécution : build release, démo locale, identifiants métier.
class AppEnvironment {
  AppEnvironment._();

  /// Autorise builds **release** sans configuration Odoo (démo interne uniquement).
  static const bool allowOfflineDemoInRelease = bool.fromEnvironment(
    'ALLOW_OFFLINE_DEMO',
    defaultValue: false,
  );

  /// Données réelles ACPEC (auth et/ou portefeuille métier) : pas de seed local.
  static bool get useAcpecLiveData =>
      OdooApiConfig.isConfigured &&
      (const bool.fromEnvironment('ODOO_USE_ACPEC_AUTH', defaultValue: false) ||
          const bool.fromEnvironment('ODOO_FUEL_ENABLED', defaultValue: false));

  /// Dépôt local seed — désactivé : toutes les données viennent de l’API.
  static bool get useLocalDemoRepositories => false;

  /// Bloque l’app en release si Odoo n’est pas configuré, sauf démo hors-ligne.
  static bool get blockReleaseWithoutApi =>
      kReleaseMode &&
      !allowOfflineDemoInRelease &&
      !OdooApiConfig.isConfigured;

  /// Builds store / Play : toutes les bases API doivent être en **HTTPS**.
  static bool get releaseRequiresHttps =>
      kReleaseMode && !allowOfflineDemoInRelease;

  static bool _urlUsesHttps(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme.toLowerCase() == 'https';
  }

  /// `true` si chaque URL configurée (Odoo, REST OTP) utilise HTTPS.
  static bool get configuredApiUrlsAreSecure {
    if (OdooApiConfig.isConfigured &&
        !_urlUsesHttps(OdooApiConfig.baseUrlTrimmed)) {
      return false;
    }
    if (AppApiConfig.isConfigured &&
        !_urlUsesHttps(AppApiConfig.baseUrlTrimmed)) {
      return false;
    }
    return true;
  }

  /// Bloque release si une URL compile-time est en HTTP (rejet App Store / Play).
  static bool get blockReleaseInsecureApi =>
      releaseRequiresHttps &&
      (OdooApiConfig.isConfigured || AppApiConfig.isConfigured) &&
      !configuredApiUrlsAreSecure;

  /// `companyId` pour l’UI : profil utilisateur, sinon valeur par défaut compile-time.
  static String companyIdForUser(AppUser? user) {
    final id = user?.companyId?.trim();
    if (id != null && id.isNotEmpty) return id;
    return AppBrandConfig.effectiveDefaultCompanyId;
  }
}
