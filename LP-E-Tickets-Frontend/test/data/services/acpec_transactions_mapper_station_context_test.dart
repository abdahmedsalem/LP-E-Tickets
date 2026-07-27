import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/acpec_transactions_mapper.dart';

void main() {
  test('station history items inherit the station name from page context', () {
    final page = AcpecTransactionsMapper.parsePage(
      {
        'ok': true,
        'data': {
          'station': {
            'station_id': 12,
            'name': 'Station Centrale',
          },
          'items': [
            {
              'id': 41,
              'transaction_type': 'consommation_station',
              'created_at': '2026-07-15 10:30:00',
              'amount_total': 500,
              'partner_id': 8,
              'partner_name': 'Client Test',
            },
          ],
        },
      },
      userId: '3',
      userName: 'Agent station',
    );

    expect(page.items, hasLength(1));
    expect(page.items.single.stationId, '12');
    expect(page.items.single.stationName, 'Station Centrale');
  });
}
