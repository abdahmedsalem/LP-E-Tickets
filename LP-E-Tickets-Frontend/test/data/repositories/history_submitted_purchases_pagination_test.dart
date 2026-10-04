import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/repositories/history_repository.dart';
import 'package:fueltoken_app/data/services/shared_services/odoo_fueltoken_facade.dart';

class _PagedPurchasesApi extends OdooFueltokenFacade {
  final calls = <Map<String, dynamic>>[];

  @override
  Future<dynamic> purchasesList([Map<String, dynamic>? params]) async {
    final request = Map<String, dynamic>.from(params ?? const {});
    calls.add(request);
    final offset = request['offset'] as int? ?? 0;
    final rows = offset == 0
        ? [
            for (var id = 1; id <= 100; id++)
              {
                'id': id,
                'name': 'PUR-$id',
                'state': 'submitted',
                'submitted_at': '2025-12-31 12:00:00',
                'create_date': '2025-12-31 12:00:00',
              },
          ]
        : [
            {
              'id': 101,
              'name': 'PUR-101',
              'state': 'submitted',
              'submitted_at': '2026-01-01 15:00:00',
              'create_date': '2026-01-01 15:00:00',
            },
          ];
    return {
      'ok': true,
      'data': {
        'items': rows,
        'count': 101,
        'limit': 100,
        'offset': offset,
        'has_more': offset == 0,
        'next_offset': offset == 0 ? 100 : null,
      },
    };
  }
}

void main() {
  test(
    'submitted purchases request inclusive dates and load every page',
    () async {
      final api = _PagedPurchasesApi();
      final repository = HistoryRepository(api: api);

      final transactions = await repository.submittedPurchases(
        userId: 'client-1',
        userName: 'Client',
        companyId: '1',
        from: DateTime(2026, 1, 1),
        // A date-picker range often supplies midnight for its final day.
        to: DateTime(2026, 1, 1),
      );

      expect(api.calls, hasLength(2));
      expect(api.calls.map((call) => call['offset']), [0, 100]);
      for (final call in api.calls) {
        expect(call['limit'], 100);
        expect(call['include_pagination_meta'], true);
        expect(call['date_from'], '2026-01-01 00:00:00');
        expect(call['date_to'], '2026-01-01 23:59:59');
      }
      expect(transactions, hasLength(1));
      expect(transactions.single.id, 'purchase-submitted-101');
    },
  );
}
