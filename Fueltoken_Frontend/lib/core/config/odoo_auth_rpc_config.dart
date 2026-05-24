import 'odoo_api_config.dart';

/// Routes d’authentification mobile ACPEC (`/api/acpec/mobile_auth/...`).
///
/// Activer avec `--dart-define=ODOO_USE_ACPEC_AUTH=true` (ou `ODOO_RPC_LOGIN_METHOD` commençant par `/`).
class OdooAuthRpcConfig {
  OdooAuthRpcConfig._();

  /// Active login / session / logout / signup ACPEC (sinon pas d’auth portail côté Odoo).
  static const bool useAcpecAuth = bool.fromEnvironment(
    'ODOO_USE_ACPEC_AUTH',
    defaultValue: false,
  );

  static const String _loginPath = String.fromEnvironment(
    'ODOO_RPC_LOGIN_PATH',
    defaultValue: '/api/acpec/mobile_auth/v1/login',
  );

  static const String _sessionPath = String.fromEnvironment(
    'ODOO_RPC_SESSION_PATH',
    defaultValue: '/api/acpec/mobile_auth/v1/session-check',
  );

  static const String _logoutPath = String.fromEnvironment(
    'ODOO_RPC_LOGOUT_PATH',
    defaultValue: '/api/acpec/mobile_auth/v1/logout',
  );

  static const String _refreshPath = String.fromEnvironment(
    'ODOO_RPC_AUTH_REFRESH_PATH',
    defaultValue: '/api/acpec/mobile_auth/v1/refresh',
  );

  static const String _mePath = String.fromEnvironment(
    'ODOO_RPC_AUTH_ME_PATH',
    defaultValue: '/api/acpec/mobile_auth/v1/me',
  );

  static const String _signupPath = String.fromEnvironment(
    'ODOO_RPC_SIGNUP_PATH',
    defaultValue: '/api/acpec/mobile_auth/v1/signup',
  );

  /// Si l’ancienne variable vaut un chemin (`/…`), elle est utilisée telle quelle.
  static const String _legacyLogin = String.fromEnvironment(
    'ODOO_RPC_LOGIN_METHOD',
    defaultValue: '',
  );

  static const String _legacySession = String.fromEnvironment(
    'ODOO_RPC_SESSION_ME_METHOD',
    defaultValue: '',
  );

  static const String _legacyLogout = String.fromEnvironment(
    'ODOO_RPC_LOGOUT_METHOD',
    defaultValue: '',
  );

  static const String _legacyComplete = String.fromEnvironment(
    'ODOO_RPC_COMPLETE_REGISTRATION_METHOD',
    defaultValue: '',
  );

  /// Société Odoo pour [signup] (params `company_id` dans la console).
  static const int signupDefaultCompanyId = int.fromEnvironment(
    'ODOO_SIGNUP_COMPANY_ID',
    defaultValue: 1,
  );

  static String get loginRoute {
    final leg = _legacyLogin.trim();
    if (leg.startsWith('/') &&
        leg.isNotEmpty &&
        !leg.contains('/acpec/fueltoken/test')) {
      return leg;
    }
    if (!useAcpecAuth) return '';
    return _loginPath.trim();
  }

  static String get sessionRoute {
    final leg = _legacySession.trim();
    if (leg.startsWith('/') &&
        leg.isNotEmpty &&
        !leg.contains('/acpec/fueltoken/test')) {
      return leg;
    }
    if (!useAcpecAuth) return '';
    return _sessionPath.trim();
  }

  static String get logoutRoute {
    final leg = _legacyLogout.trim();
    if (leg.startsWith('/') &&
        leg.isNotEmpty &&
        !leg.contains('/acpec/fueltoken/test')) {
      return leg;
    }
    if (!useAcpecAuth) return '';
    return _logoutPath.trim();
  }

  /// Rafraîchissement des jetons (`X-ACPEC-Refresh-Token` ou corps JSON-RPC).
  static String get refreshRoute {
    if (!useAcpecAuth) return '';
    return _refreshPath.trim();
  }

  /// Profil session courante (Bearer), distinct de [sessionRoute] si besoin.
  static String get meRoute {
    if (!useAcpecAuth) return '';
    return _mePath.trim();
  }

  /// Inscription mobile ACPEC (`/api/acpec/mobile_auth/v1/signup`), sur l’hôte Odoo.
  /// Disponible dès que [OdooApiConfig] est renseigné (OTP REST optionnel côté `API_BASE_URL`).
  static String get signupRoute {
    final leg = _legacyComplete.trim();
    if (leg.startsWith('/') &&
        leg.isNotEmpty &&
        !leg.contains('/acpec/fueltoken/test')) {
      return leg;
    }
    final p = _signupPath.trim();
    if (p.isEmpty) return '';
    if (OdooApiConfig.isConfigured) return p;
    if (useAcpecAuth) return p;
    return '';
  }

  static bool get hasLogin => loginRoute.isNotEmpty;

  static bool get hasSessionMe => sessionRoute.isNotEmpty;

  static bool get hasCompleteRegistration => signupRoute.isNotEmpty;
}
