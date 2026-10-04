import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/repositories/portfolio_repository.dart';
import 'package:fueltoken_app/data/services/purchase_services/acpec_carnet_catalog_service.dart';
import 'package:fueltoken_app/data/services/shared_services/odoo_fueltoken_facade.dart';
import 'package:fueltoken_app/domain/models/purchase/carnet_catalog_load_result.dart';

class _PagedQrApi implements OdooFueltokenFacade {
  final requests = <Map<String, dynamic>>[];

  @override
  Future<dynamic> qrList([Map<String, dynamic>? params]) async {
    final request = params ?? const <String, dynamic>{};
    requests.add(Map<String, dynamic>.from(request));
    final offset = request['offset'] as int;
    final remaining = 101 - offset;
    final count = remaining.clamp(0, 100);
    return {
      'ok': true,
      'data': {
        'items': [
          for (var i = 0; i < count; i++)
            {
              'id': offset + i + 1,
              'public_code': 'QR-${offset + i + 1}',
              'state': 'active',
              'created_at': '2026-10-01 12:00:00',
              'amount_total': 100,
              'qty_total': 1,
            },
        ],
        'count': 101,
        'has_more': offset + count < 101,
        'next_offset': offset + count < 101 ? offset + count : null,
      },
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyCatalog extends AcpecCarnetCatalogService {
  @override
  Future<AcpecCarnetCatalogLoadResult> loadMobileCatalogFacesOnly({
    required String companyId,
    String? languageCode,
  }) async => const AcpecCarnetCatalogLoadResult(types: []);
}

void main() {
  test(
    'Mes QR loads every server page and keeps the selected state filter',
    () async {
      final api = _PagedQrApi();
      final repository = PortfolioRepository(
        api: api,
        catalogService: _EmptyCatalog(),
      );

      final qrs = await repository.qrs(
        const {'state': 'active'},
        ownerId: '1',
        ownerName: 'Client',
        companyId: '1',
      );

      expect(qrs, hasLength(101));
      expect(api.requests.map((request) => request['offset']), [0, 100]);
      expect(
        api.requests.every((request) => request['state'] == 'active'),
        true,
      );
      expect(
        api.requests.every(
          (request) => request['include_pagination_meta'] == true,
        ),
        true,
      );
    },
  );
}
