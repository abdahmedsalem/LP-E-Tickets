import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/models/business_transaction.dart';
import 'package:fueltoken_app/data/services/acpec_transactions_mapper.dart';

void main() {
  group('AcpecTransactionsMapper qr name', () {
    test('maps qr_name and prefers it for station display', () {
      final page = AcpecTransactionsMapper.parsePage(
        {
          'ok': true,
          'items': [
            {
              'id': 701,
              'name': 'TX-20260706-QR-001',
              'transaction_type': 'consommation_station',
              'amount_total': 500,
              'qty_total': 1,
              'created_at': '2026-07-06 08:25:00',
              'partner_id': 42342004,
              'partner_name': '42342004 - Test4',
              'qr_id': 2759,
              'qr_name': 'QR/2026/000123',
              'qr_public_code': 'QR-UheNX-LONG',
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
      expect(tx.qrName, 'QR/2026/000123');
      expect(tx.qrDisplayName, 'QR/2026/000123');
    });

    test('falls back to qr id before public code', () {
      final tx = BusinessTransaction(
        id: 'tx-1',
        type: TxType.stationConsumption,
        date: DateTime(2026, 7, 6),
        userId: 'u1',
        userName: '42342004 - Test4',
        lines: const [],
        qrId: '2759',
        qrPublicCode: 'QR-UheNX-LONG',
      );

      expect(tx.qrDisplayName, '2759');
    });
  });
}
