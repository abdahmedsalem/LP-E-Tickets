import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/acpec_qr_mapper.dart';

void main() {
  test('QR detail keeps the localized carnet name from technical lines', () {
    const arabicName = 'دفتر - 10 تذاكر × 100 أوقية';
    final qr = AcpecQrMapper.fromRpcEnvelope(
      {
        'data': {
          'id': 12,
          'public_code': 'QR-TEST-12',
          'state': 'active',
          'generated_at': '2026-07-20 10:00:00',
          'technical_lines': [
            {
              'qr_line_id': 31,
              'face_line_id': 41,
              'purchase_id': 51,
              'carnet_type_id': 61,
              'carnet_type_code': 'C10T-100',
              'carnet_type_name': arabicName,
              'face_count': 10,
              'face_value': 100,
              'qty': 2,
              'expires_at': '2027-07-20 10:00:00',
            },
          ],
        },
      },
      ownerId: '1',
      ownerName: 'Client',
      companyId: '1',
    );

    expect(qr.lines, hasLength(1));
    expect(qr.lines.first.carnetTypeName, arabicName);
  });
}
