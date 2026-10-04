import '../../domain/models/portfolio/face_line.dart';
import '../../domain/models/qr/qr_token.dart';
import '../../domain/models/purchase/carnet_type.dart';
import '../../domain/models/purchase/carnet_catalog_load_result.dart';
import '../../domain/repositories/portfolio_repository.dart';
import '../services/shared_services/odoo_fueltoken_facade.dart';
import '../services/portfolio_services/acpec_faces_mapper.dart';
import '../services/qr_services/acpec_qr_mapper.dart';
import '../services/purchase_services/acpec_carnet_catalog_service.dart';
import '../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';

class PortfolioRepository implements PortfolioRepositoryContract {
  PortfolioRepository({
    OdooFueltokenFacade? api,
    AcpecCarnetCatalogService? catalogService,
  }) : _api = api ?? OdooFueltokenFacade(),
       _catalogService = catalogService ?? AcpecCarnetCatalogService.instance;

  final OdooFueltokenFacade _api;
  final AcpecCarnetCatalogService _catalogService;
  static const int _qrPageSize = 100;
  static const int _maxQrPages = 100;
  @override
  Future<AcpecCarnetCatalogLoadResult> catalog({
    required String companyId,
    String? languageCode,
  }) => _catalogService.loadMobileCatalogFacesOnly(
    companyId: companyId,
    languageCode: languageCode,
  );

  @override
  Future<List<CarnetType>> purchaseOfferTypes({required String companyId}) =>
      _catalogService.listPurchaseOfferTypes(companyId: companyId);
  Future<AcpecCarnetCatalogLoadResult> optionalCatalog({
    required String companyId,
    String? languageCode,
  }) async {
    try {
      return await catalog(companyId: companyId, languageCode: languageCode);
    } catch (_) {
      return const AcpecCarnetCatalogLoadResult(types: []);
    }
  }

  @override
  Future<List<FaceLine>> faces({
    required String ownerId,
    required String companyId,
    String? languageCode,
  }) async {
    final rawFuture = _api.faces(const {});
    final typesFuture = optionalCatalog(
      companyId: companyId,
      languageCode: languageCode,
    );
    final raw = await rawFuture;
    return AcpecCarnetCatalogService.localizeFaceLinesByCarnetTypes(
      lines: AcpecFacesMapper.fromRpcResult(raw, ownerId: ownerId),
      types: (await typesFuture).types,
    );
  }

  @override
  Future<List<QrToken>> qrs(
    Map<String, dynamic> params, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) async {
    final typesFuture = optionalCatalog(companyId: companyId);
    final all = <QrToken>[];
    var offset = (params['offset'] as int?) ?? 0;
    for (var pageNumber = 0; pageNumber < _maxQrPages; pageNumber++) {
      final request = <String, dynamic>{
        ...params,
        'limit': _qrPageSize,
        'offset': offset,
        'include_pagination_meta': true,
      };
      final raw = await _api.qrList(request);
      final page = AcpecQrMapper.listPageFromRpc(
        raw,
        ownerId: ownerId,
        ownerName: ownerName,
        companyId: companyId,
        requestedLimit: _qrPageSize,
        requestedOffset: offset,
      );
      all.addAll(page.items);
      if (!page.hasMore) break;
      if (page.nextOffset <= offset) {
        throw const FormatException('Pagination QR invalide.');
      }
      offset = page.nextOffset;
      if (pageNumber == _maxQrPages - 1) {
        throw StateError('La liste des QR dépasse la limite de pagination.');
      }
    }
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return AcpecCarnetCatalogService.localizeQrTokensByCarnetTypes(
      qrs: all,
      types: (await typesFuture).types,
    );
  }

  @override
  void invalidateQrs(Map<String, dynamic> params, {bool allVariants = false}) {
    if (allVariants) {
      AcpecFueltokenRpcCoordinator.shared.invalidateRoute(
        OdooFueltokenRpcConfig.qrList,
      );
      return;
    }
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.qrList,
      params,
    );
  }
}
