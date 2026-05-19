import 'package:flutter/foundation.dart';

import '../config/app_api_config.dart';
import '../config/odoo_api_config.dart';
import '../config/odoo_auth_rpc_config.dart';

/// Imprime la config réseau ACPEC dans le terminal `flutter run` (stdout).
///
/// L’URL `http://127.0.0.1:xxxxx/...` affichée par Flutter est **DevTools** sur votre Mac,
/// pas le serveur Odoo — le host API est celui de `ODOO_JSONRPC_BASE_URL`.
void debugPrintAcpecNetworkSummary() {
  final raw = OdooApiConfig.baseUrl.trim();
  final bt = OdooApiConfig.baseUrlTrimmed;
  final loginPath = OdooAuthRpcConfig.loginRoute;

  debugPrint('');
  debugPrint('╔══════════════════════════════════════════════════════════════╗');
  debugPrint('║ ACPEC Odoo — API (ceci N’est PAS l’URL DevTools 127.0.0.1)  ║');
  debugPrint('╚══════════════════════════════════════════════════════════════╝');
  debugPrint(
    'ODOO_JSONRPC_BASE_URL (dart-define) : '
    '${raw.isEmpty ? 'VIDE — ajoutez --dart-define=ODOO_JSONRPC_BASE_URL=https://votre-odoo.example' : raw}',
  );
  debugPrint(
    'Origine utilisée (baseUrlTrimmed)    : ${bt.isEmpty ? 'VIDE' : bt}',
  );
  debugPrint(
    'ODOO_USE_ACPEC_AUTH                  : ${OdooAuthRpcConfig.useAcpecAuth}',
  );
  debugPrint(
    'Route login (Se connecter)          : ${loginPath.isEmpty ? '(vide — auth ACPEC désactivée ou route manquante)' : loginPath}',
  );
  if (bt.isNotEmpty && loginPath.isNotEmpty) {
    debugPrint('Exemple URL login (comme Postman)     : $bt$loginPath');
  }
  debugPrint(
    'Logs détail chaque POST JSON-RPC     : kDebug=$kDebugMode ou ODOO_DEBUG_RPC=true',
  );
  debugPrint(
    'API_BASE_URL (REST OTP optionnel)   : '
    '${AppApiConfig.isConfigured ? AppApiConfig.baseUrlTrimmed : 'VIDE'} '
    '(inscription / OTP si vous exposez ces routes sur un service externe)',
  );
  debugPrint('');
}
