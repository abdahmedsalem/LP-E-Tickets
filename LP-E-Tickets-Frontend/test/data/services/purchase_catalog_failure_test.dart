import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/purchase_services/acpec_carnet_catalog_service.dart';
import 'package:fueltoken_app/domain/models/purchase/carnet_catalog_load_result.dart';

class StubPurchaseCatalog extends AcpecCarnetCatalogService {
  StubPurchaseCatalog(this.result);
  final AcpecCarnetCatalogLoadResult result;

  @override
  Future<AcpecCarnetCatalogLoadResult> loadCatalog({
    required String companyId,
    String? languageCode,
  }) async => result;
}

void main() {
  test('a successful empty catalog remains empty', () async {
    final catalog = StubPurchaseCatalog(
      const AcpecCarnetCatalogLoadResult(types: []),
    );
    expect(await catalog.listPurchaseOfferTypes(companyId: '1'), isEmpty);
  });
  test('failure of every source is reported to the purchase screen', () async {
    final catalog = StubPurchaseCatalog(
      const AcpecCarnetCatalogLoadResult(
        types: [],
        carnetTypesError: 'offline',
        facesError: 'offline',
        walletError: 'offline',
        purchasesError: 'offline',
      ),
    );
    await expectLater(
      catalog.listPurchaseOfferTypes(companyId: '1'),
      throwsException,
    );
  });
  test(
    'an available fallback is not treated as a total loading failure',
    () async {
      final catalog = StubPurchaseCatalog(
        const AcpecCarnetCatalogLoadResult(
          types: [],
          carnetTypesError: 'offline',
          facesError: 'offline',
          purchasesError: 'offline',
        ),
      );
      expect(await catalog.listPurchaseOfferTypes(companyId: '1'), isEmpty);
    },
  );
}
