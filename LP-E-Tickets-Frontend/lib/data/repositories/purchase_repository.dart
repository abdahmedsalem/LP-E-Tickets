import '../../domain/models/purchase/carnet_type.dart';
import '../../domain/models/purchase/payment_method.dart';
import '../../domain/models/purchase/purchase_receipt.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../services/shared_services/odoo_fueltoken_facade.dart';
import '../services/purchase_services/acpec_carnet_catalog_service.dart';
import '../services/purchase_services/acpec_payment_methods_service.dart';
import '../services/purchase_services/acpec_purchases_mapper.dart';

class PurchaseRepository implements PurchaseRepositoryContract {
  PurchaseRepository({
    OdooFueltokenFacade? api,
    AcpecCarnetCatalogService? catalogService,
  }) : _api = api ?? OdooFueltokenFacade(),
       _catalogService = catalogService ?? AcpecCarnetCatalogService.instance;

  final OdooFueltokenFacade _api;
  final AcpecCarnetCatalogService _catalogService;
  @override
  Future<List<CarnetType>> listPurchaseOfferTypes({
    required String companyId,
  }) => _catalogService.listPurchaseOfferTypes(companyId: companyId);
  @override
  Future<List<PaymentMethod>> listPaymentMethods() =>
      AcpecPaymentMethodsService.listActive();
  @override
  Future<AcpecPurchaseCreateResult> purchasesCreate(
    Map<String, dynamic> params,
  ) async => AcpecPurchasesMapper.parseCreateResult(
    await _api.purchasesCreate(params),
  );
}
