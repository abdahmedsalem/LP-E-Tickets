import '../../core/config/odoo_api_config.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../core/settings/app_preferences.dart';
import '../services/odoo_jsonrpc_client.dart';

/// Client JSON-RPC vers les routes métier ACPEC.
class AcpecFueltokenJsonRpcApi {
  AcpecFueltokenJsonRpcApi({
    OdooJsonRpcClient? client,
    AcpecFueltokenRpcCoordinator? coordinator,
  }) : _client = client ?? OdooJsonRpcClient(),
       _coordinator = coordinator ?? AcpecFueltokenRpcCoordinator.shared;

  final OdooJsonRpcClient _client;
  final AcpecFueltokenRpcCoordinator _coordinator;

  /// [route] : chemin absolu serveur (ex. `/api/acpec/...`).
  Future<dynamic> callRoute(
    String route, {
    Map<String, dynamic>? params,
  }) async {
    var r = _normalizeRoute(route);
    final languageCode = await AppPreferences.localeCode();
    return _coordinator.execute(
      route: r,
      params: params,
      cacheVariant: 'locale=$languageCode',
      request: () => _client.postJsonRpc(path: r, params: params),
    );
  }

  /// Appel technique sans Cookie / X-Acpec-Session / Authorization.
  ///
  /// Utilisé surtout pour `/refresh` : au démarrage de l'application, l'access
  /// token local peut être expiré. Il ne faut pas l'envoyer avec la requête de
  /// renouvellement, sinon une ancienne session courte peut perturber le test
  /// de session longue.
  Future<dynamic> callRouteWithoutSession(
    String route, {
    Map<String, dynamic>? params,
    Map<String, String>? extraHeaders,
  }) {
    var r = _normalizeRoute(route);
    return _client.postJsonRpc(
      path: r,
      params: params,
      extraHeaders: extraHeaders,
      omitSessionHeaders: true,
      suppressAuthRecovery: true,
    );
  }

  static String _normalizeRoute(String route) {
    var r = route.trim();
    if (r.isEmpty) {
      throw StateError('route ACPEC vide.');
    }
    if (!r.startsWith('/')) {
      r = '/$r';
    }
    return r;
  }

  @Deprecated('Utiliser callRoute avec le chemin complet.')
  String get legacyControllerPath => OdooApiConfig.controllerPathNormalized;
}
