import '../../domain/models/purchase/carnet_type.dart';
import '../../domain/models/purchase/carnet_flow_data.dart';
import '../services/portfolio_services/acpec_faces_mapper.dart';
import '../services/shared_services/odoo_fueltoken_facade.dart';
import '../services/purchase_services/acpec_carnet_catalog_service.dart';

/// Shared catalogue access for QR generation and transfers.
class CarnetFlowRepository {
  CarnetFlowRepository({OdooFueltokenFacade? api})
    : api = api ?? OdooFueltokenFacade();
  final OdooFueltokenFacade api;

  Future<CarnetFlowData> loadFaces({
    required String ownerId,
    required String companyId,
    bool transferableOnly = false,
    bool mobileCatalog = false,
  }) async {
    final raw = await api.faces(
      transferableOnly
          ? const <String, dynamic>{'transferable_only': true}
          : const <String, dynamic>{},
    );
    final types = mobileCatalog
        ? (await AcpecCarnetCatalogService.instance.loadMobileCatalogFacesOnly(
            companyId: companyId,
          )).types
        : await AcpecCarnetCatalogService.instance
              .listPurchaseOfferTypes(companyId: companyId)
              .catchError((_) => <CarnetType>[]);
    return CarnetFlowData(
      types: types,
      faces: AcpecCarnetCatalogService.localizeFaceLinesByCarnetTypes(
        lines: AcpecFacesMapper.fromRpcResult(raw, ownerId: ownerId),
        types: types,
      ),
    );
  }
}
