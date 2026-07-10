import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/models/business_transaction.dart';
import 'package:fueltoken_app/data/services/acpec_transactions_mapper.dart';

void main() {
  group('AcpecTransactionsMapper ticket transfer', () {
    test('maps ticket transfer as outgoing (transfer)', () {
      final page = AcpecTransactionsMapper.parsePage(
        {
          'ok': true,
          'items': [
            {
              'id': 801,
              'name': 'TX-20260707-TT-001',
              'transaction_type': 'ticket_transfer',
              'amount_total': 1500,
              'qty_total': 1,
              'created_at': '2026-07-07 09:15:00',
              'partner_id': 9,
              'partner_name': 'Client Source',
              'ticket_transfer_id': 100,
              'ticket_transfer_direction': 'outgoing',
              'ticket_transfer_other_party': 'Client Destination',
              'lines': [
                {
                  'id': 1,
                  'face_value': 1500,
                  'qty': 1,
                  'amount': 1500,
                }
              ],
            },
          ],
          'count': 1,
          'has_more': false,
        },
        userId: 'client-source-user',
        userName: 'Client Source',
      );

      expect(page.items, hasLength(1));
      final tx = page.items.single;
      expect(tx.type, TxType.carnetTransfer);
      expect(tx.transferIsIncoming, isFalse);
      expect(tx.displayTitle, 'Transfert de tickets');
      expect(tx.transferParty, 'Client Destination');
    });

    test('maps ticket transfer as incoming (reception)', () {
      final page = AcpecTransactionsMapper.parsePage(
        {
          'ok': true,
          'items': [
            {
              'id': 802,
              'name': 'TX-20260707-TT-002',
              'transaction_type': 'ticket_transfer',
              'amount_total': 1500,
              'qty_total': 1,
              'created_at': '2026-07-07 09:16:00',
              'partner_id': 10,
              'partner_name': 'Client Destination',
              'ticket_transfer_id': 100,
              'ticket_transfer_direction': 'incoming',
              'ticket_transfer_other_party': 'Client Source',
              'lines': [
                {
                  'id': 1,
                  'face_value': 1500,
                  'qty': 1,
                  'amount': 1500,
                }
              ],
            },
          ],
          'count': 1,
          'has_more': false,
        },
        userId: 'client-dest-user',
        userName: 'Client Destination',
      );

      expect(page.items, hasLength(1));
      final tx = page.items.single;
      expect(tx.type, TxType.carnetReceived);
      expect(tx.transferIsIncoming, isTrue);
      expect(tx.displayTitle, 'Réception de tickets');
      expect(tx.transferParty, 'Client Source');
    });
  });
}
