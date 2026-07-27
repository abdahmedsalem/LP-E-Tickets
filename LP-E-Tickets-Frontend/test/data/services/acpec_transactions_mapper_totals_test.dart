import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/services/acpec_transactions_mapper.dart';

void main() {
  group('AcpecTransactionsMapper totals', () {
    test('maps backend totals independently from page items', () {
      final page = AcpecTransactionsMapper.parsePage(
        {
          'ok': true,
          'items': [
            {
              'id': 701,
              'name': 'TX-20260706-001',
              'transaction_type': 'consommation_station',
              'amount_total': 120,
              'qty_total': 1,
              'created_at': '2026-07-06 09:00:00',
              'partner_id': 42342004,
              'partner_name': '42342004 - Test4',
              'regularization_state': 'pending',
            },
          ],
          'count': 12,
          'has_more': true,
          'totals': {
            'scope': 'filtered',
            'regularization_state': 'pending',
            'qr_count': 12,
            'transaction_count': 12,
            'amount_total': 1440,
            'qty_total': 12,
          },
        },
        userId: 'station-user',
        userName: 'Agent Station',
        requestedLimit: 1,
        requestedOffset: 0,
      );

      expect(page.items, hasLength(1));
      expect(page.totalCount, 12);
      expect(page.hasMore, isTrue);
      expect(page.totals, isNotNull);
      expect(page.totals!.scope, 'filtered');
      expect(page.totals!.regularizationState, 'pending');
      expect(page.totals!.qrCount, 12);
      expect(page.totals!.transactionCount, 12);
      expect(page.totals!.amountTotal, 1440);
      expect(page.totals!.qtyTotal, 12);
    });

    test('keeps backend amount_total signed', () {
      final page = AcpecTransactionsMapper.parsePage(
        {
          'ok': true,
          'items': const [],
          'count': 0,
          'has_more': false,
          'totals': {
            'scope': 'filtered',
            'regularization_state': 'all',
            'qr_count': 0,
            'amount_total': -250,
            'qty_total': 0,
          },
        },
        userId: 'station-user',
        userName: 'Agent Station',
      );

      expect(page.totals, isNotNull);
      expect(page.totals!.amountTotal, -250);
    });
  });
}
