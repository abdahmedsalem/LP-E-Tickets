import '../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../domain/models/portfolio/wallet_snapshot.dart';
import '../../domain/models/purchase/carnet_catalog_load_result.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../services/portfolio_services/acpec_wallet_mapper.dart';
import '../services/purchase_services/acpec_carnet_catalog_service.dart';
import '../services/shared_services/odoo_fueltoken_facade.dart';

class WalletRepository implements WalletRepositoryContract {
  WalletRepository({
    OdooFueltokenFacade? facade,
    AcpecCarnetCatalogService? catalogService,
  }) : _facade = facade ?? OdooFueltokenFacade(),
       _catalogService = catalogService ?? AcpecCarnetCatalogService.instance;

  final OdooFueltokenFacade _facade;
  final AcpecCarnetCatalogService _catalogService;

  @override
  Future<WalletSnapshot> current({
    required String ownerId,
    required String companyId,
  }) async {
    final params = Map<String, dynamic>.from(
      OdooFueltokenRpcConfig.walletCurrentDefaultParams,
    );
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.walletCurrent,
      params,
    );
    final catalogFuture = _catalogService
        .loadMobileCatalogFacesOnly(companyId: companyId)
        .catchError((_) => const AcpecCarnetCatalogLoadResult(types: []));
    final raw = await _facade.walletCurrent(params);
    final mapped = AcpecWalletMapper.fromRpcResult(raw, ownerId: ownerId);
    final catalog = await catalogFuture;
    final localizedBreakdown =
        AcpecCarnetCatalogService.localizeCarnetTypeBreakdownByCarnetTypes(
          value: mapped.extras?.breakdownByCarnetType,
          types: catalog.types,
        );
    return WalletSnapshot(
      amount: mapped.amount,
      byFaceValue: mapped.byFaceValue,
      faceLines: AcpecCarnetCatalogService.localizeFaceLinesByCarnetTypes(
        lines: mapped.faceLines,
        types: catalog.types,
      ),
      breakdownExtras: mapped.extras?.copyWith(
        breakdownByCarnetType:
            localizedBreakdown ?? mapped.extras?.breakdownByCarnetType,
      ),
    );
  }
}
