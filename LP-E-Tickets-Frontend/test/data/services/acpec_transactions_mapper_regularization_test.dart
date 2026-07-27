import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/models/business_transaction.dart';
import 'package:fueltoken_app/data/services/acpec_transactions_mapper.dart';

void main() {
  group('AcpecTransactionsMapper regularization fields', () {
    test('maps station regularization state, reference and date', () {
      final page = AcpecTransactionsMapper.parsePage(
        {
          'ok': true,
          'items': [
            {
              'id': 501,
              'name': 'TX-20260705-REG-001',
              'transaction_type': 'consommation_station',
              'amount_total': 2500,
              'qty_total': 1,
              'created_at': '2026-07-05 10:30:00',
              'station_id': 7,
              'station_name': 'Station Test',
              'partner_id': 9,
              'partner_name': 'Client Test',
              'qr_id': 22,
              'qr_public_code': 'QR-TEST-001',
              'regularization_state': 'regularized',
              'regularization_reference': 'REG/2026/0001',
              'regularization_date': '2026-07-05 11:45:00',
            },
          ],
          'count': 1,
          'has_more': false,
        },
        userId: 'station-user',
        userName: 'Agent Station',
      );

      expect(page.items, hasLength(1));
      final tx = page.items.single;
      expect(tx.type, TxType.stationConsumption);
      expect(tx.regularizationState, 'regularized');
      expect(tx.isRegularized, isTrue);
      expect(tx.regularizationLabel, 'Régularisé');
      expect(tx.regularizationReference, 'REG/2026/0001');
      expect(tx.regularizationDate, isNotNull);
    });

    test('defaults empty regularization state to non regularized', () {
      final tx = BusinessTransaction(
        id: 'tx-1',
        type: TxType.stationConsumption,
        date: DateTime(2026, 7, 5),
        userId: 'u1',
        userName: 'Agent',
        lines: const [],
      );

      expect(tx.effectiveRegularizationState, 'pending');
      expect(tx.isRegularized, isFalse);
      expect(tx.regularizationLabel, 'Non régularisé');
    });
  });
}
