import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/models/purchase_lot.dart';
import 'package:fueltoken_app/data/services/acpec_purchases_mapper.dart';

void main() {
  group('AcpecPurchasesMapper', () {
    test('keeps backend purchase lines with carnet type name, quantity and amount inputs', () {
      final lots = AcpecPurchasesMapper.fromRpcResult(
        {
          'data': {
            'items': [
              {
                'id': 15,
                'name': 'ACH/2026/00015',
                'public_code': 'PUR-15',
                'state': 'approved',
                'submitted_at': '2026-06-04 10:00:00',
                'approved_at': '2026-06-04 10:05:00',
                'lines': [
                  {
                    'id': 91,
                    'carnet_type_id': 7,
                    'carnet_type_code': 'C10-1000',
                    'carnet_type_name': 'Carnet 10 × 1000',
                    'carnet_qty': 3,
                    'face_count': 10,
                    'face_value': 1000,
                    'amount_total': 30000,
                  },
                ],
              },
            ],
          },
        },
        clientId: 'user-1',
        clientName: 'Client Test',
        companyId: '1',
      );

      expect(lots, hasLength(1));
      expect(lots.first.state, PurchaseLotState.approved);
      expect(lots.first.lines, hasLength(1));
      expect(lots.first.lines.first.carnetTypeName, 'Carnet 10 × 1000');
      expect(lots.first.lines.first.carnetCount, 3);
      expect(lots.first.lines.first.carnetSize, 10);
      expect(lots.first.lines.first.faceValue, 1000);
      expect(lots.first.lines.first.lineAmount, 30000);
    });
  });
}
