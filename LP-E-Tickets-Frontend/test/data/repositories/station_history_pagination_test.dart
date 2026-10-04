import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/repositories/station_repository.dart';
import 'package:fueltoken_app/data/services/purchase_services/acpec_carnet_catalog_service.dart';
import 'package:fueltoken_app/data/services/shared_services/odoo_fueltoken_facade.dart';
import 'package:fueltoken_app/domain/models/purchase/carnet_catalog_load_result.dart';

class _PagedStationApi implements OdooFueltokenFacade {
  final calls = <Map<String, dynamic>>[];

  @override
  Future<dynamic> stationTransactions(Map<String, dynamic> params) async {
    calls.add(Map<String, dynamic>.from(params));
    final offset = params['offset'] as int;
    final id = offset + 1;
    return {
      'ok': true,
      'data': {
        'items': [
          {
            'id': id,
            'transaction_type': 'consommation_station',
            'created_at': '2026-09-0$id 12:00:00',
            'amount_total': 1000 * id,
            'qty_total': 1,
            'qr_id': id,
            'qr_public_code': 'QR-$id',
            'station_id': 3,
            'station_name': 'Station Test',
          },
        ],
        'total_count': 2,
        'totals': {
          'qr_count': 2,
          'transaction_count': 2,
          'amount_total': 3000,
          'qty_total': 2,
        },
      },
      'has_more': offset == 0,
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
    'station history preserves date filters and advances by raw page offset',
    () async {
      final api = _PagedStationApi();
      final repository = StationRepository(
        facade: api,
        catalogService: _EmptyCatalog(),
      );
      const range = {
        'limit': 1,
        'offset': 0,
        'include_pagination_meta': true,
        'date_from': '2026-09-01 00:00:00',
        'date_to': '2026-09-30 23:59:59',
      };

      final first = await repository.consumptionHistory(
        params: range,
        userId: '1',
        userName: 'Agent',
        companyId: '1',
      );
      final second = await repository.consumptionHistory(
        params: {...range, 'offset': 1},
        userId: '1',
        userName: 'Agent',
        companyId: '1',
      );

      expect(api.calls, hasLength(2));
      expect(api.calls.map((call) => call['offset']), [0, 1]);
      expect(
        api.calls.every((call) => call['date_from'] == range['date_from']),
        true,
      );
      expect(
        api.calls.every((call) => call['date_to'] == range['date_to']),
        true,
      );
      expect(first.items.single.id, '1');
      expect(first.hasMore, true);
      expect(first.totals?.amountTotal, 3000);
      expect(second.items.single.id, '2');
      expect(second.hasMore, false);
    },
  );
}
