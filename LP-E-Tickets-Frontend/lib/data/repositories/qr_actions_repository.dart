import '../../domain/models/qr/qr_token.dart';
import '../../domain/models/purchase/carnet_catalog_load_result.dart';
import '../../domain/repositories/qr_actions_repository.dart';
import '../services/shared_services/odoo_fueltoken_facade.dart';
import '../services/qr_services/acpec_qr_mapper.dart';
import '../services/purchase_services/acpec_carnet_catalog_service.dart';
import '../services/shared_services/acpec_rpc_result_guard.dart';
import '../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';

class QrActionsRepository implements QrActionsRepositoryContract {
  QrActionsRepository({OdooFueltokenFacade? api})
    : _api = api ?? OdooFueltokenFacade();
  final OdooFueltokenFacade _api;
  @override
  Future<QrToken> loadDetail(
    String routeId, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) async {
    final params = AcpecQrMapper.detailParamsForRouteId(routeId);
    invalidateDetail(routeId);
    final detail = _api.qrDetail(params);
    final catalog = AcpecCarnetCatalogService.instance
        .loadMobileCatalogFacesOnly(companyId: companyId)
        .catchError((_) => const AcpecCarnetCatalogLoadResult(types: []));
    final raw = await detail;
    final types = (await catalog).types;
    return AcpecCarnetCatalogService.localizeQrTokenByCarnetTypes(
      qr: parseQr(
        raw,
        ownerId: ownerId,
        ownerName: ownerName,
        companyId: companyId,
      ),
      types: types,
    );
  }

  @override
  QrToken parseQr(
    dynamic raw, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) => AcpecQrMapper.fromRpcEnvelope(
    raw,
    ownerId: ownerId,
    ownerName: ownerName,
    companyId: companyId,
  );
  @override
  void invalidateDetail(String routeId) =>
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.qrDetail,
        AcpecQrMapper.detailParamsForRouteId(routeId),
      );
  @override
  void invalidateList() => AcpecFueltokenRpcCoordinator.shared.invalidateRoute(
    OdooFueltokenRpcConfig.qrList,
  );
  @override
  Future<Map<String, dynamic>> qrSeparer(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  }) async => acpecRpcMapOrThrow(
    await _api.qrSeparer(params),
    fallbackMessage: fallbackMessage,
    publicErrorMessage: publicErrorMessage,
  );
  @override
  Future<Map<String, dynamic>> qrRetirer(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  }) async => acpecRpcMapOrThrow(
    await _api.qrRetirer(params),
    fallbackMessage: fallbackMessage,
    publicErrorMessage: publicErrorMessage,
  );
  @override
  Future<Map<String, dynamic>> qrRevealCode(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  }) async => acpecRpcMapOrThrow(
    await _api.qrRevealCode(params),
    fallbackMessage: fallbackMessage,
    publicErrorMessage: publicErrorMessage,
  );
}
