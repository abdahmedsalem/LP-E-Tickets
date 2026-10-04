import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/station_services/station_qr_check_mapper.dart';

void main() {
  test('expired reservation allows cancellation but never consumption', () {
    final result = StationQrCheckMapper.fromRpc({
      'data': {
        'state': 'expired',
        'can_consume': false,
        'can_cancel': true,
        'reservation_id': 'reservation-A',
      },
    });
    expect(result.canConsume, isFalse);
    expect(result.canCancel, isTrue);
    expect(result.reservationId, 'reservation-A');
  });

  test('missing cancellation permission defaults to false', () {
    final result = StationQrCheckMapper.fromRpc({
      'data': {'state': 'active', 'can_consume': true},
    });
    expect(result.canConsume, isTrue);
    expect(result.canCancel, isFalse);
    expect(result.reservationId, isNull);
  });
}
