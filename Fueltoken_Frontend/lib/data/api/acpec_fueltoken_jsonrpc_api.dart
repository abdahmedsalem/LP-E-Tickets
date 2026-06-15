import '../../core/config/odoo_api_config.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';
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
  Future<dynamic> callRoute(String route, {Map<String, dynamic>? params}) {
    var r = route.trim();
    if (r.isEmpty) {
      throw StateError('route ACPEC vide.');
    }
    if (!r.startsWith('/')) {
      r = '/$r';
    }
    return _coordinator.execute(
      route: r,
      params: params,
      request: () => _client.postJsonRpc(path: r, params: params),
    );
  }

  @Deprecated('Utiliser callRoute avec le chemin complet.')
  String get legacyControllerPath => OdooApiConfig.controllerPathNormalized;
}
