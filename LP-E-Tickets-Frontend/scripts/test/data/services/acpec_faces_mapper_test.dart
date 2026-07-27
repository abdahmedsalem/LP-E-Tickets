import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/services/acpec_faces_mapper.dart';

void main() {
  group('AcpecFacesMapper', () {
    test('keeps carnet type name from backend aliases', () {
      final rows = AcpecFacesMapper.fromRpcResult(
        {
          'data': {
            'lines': [
              {
                'id': 1,
                'purchase_id': 10,
                'line_id': 20,
                'carnet_type_id': '7',
                'carnet_type_code': 'C10-1000',
                'name': 'Carnet 10 * 1000',
                'face_value': 1000,
                'qty_available': 4,
                'initial_qty': 4,
                'qty_qr_active': 0,
                'qty_qr_blocked': 0,
                'qty_consumed': 0,
                'qty_expired': 0,
                'expiration_date': '2026-12-31 00:00:00',
              },
            ],
          },
        },
        ownerId: 'user-1',
      );

      expect(rows, hasLength(1));
      expect(rows.first.carnetTypeName, 'Carnet 10 * 1000');
    });
  });
}
