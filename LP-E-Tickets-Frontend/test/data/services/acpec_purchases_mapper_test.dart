import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/models/purchase_lot.dart';
import 'package:fueltoken_app/data/services/acpec_purchases_mapper.dart';

void main() {
  group('AcpecPurchasesMapper', () {
    test(
      'keeps backend purchase lines with carnet type name, quantity and amount inputs',
      () {
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
      },
    );

    test('decodes mobile purchase detail proof data for image preview', () {
      final proofData = base64Encode([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        ...utf8.encode('proof'),
      ]);

      final lot = AcpecPurchasesMapper.parsePurchaseDetail(
        {
          'data': {
            'id': 18,
            'name': 'ACH/2026/00018',
            'public_code': 'PUR-18',
            'state': 'submitted',
            'amount_total': 1000,
            'face_qty_total': 1,
            'payment_reference': 'PAY-18',
            'proof_attachments': [
              {
                'id': 44,
                'name': 'preuve.png',
                'filename': 'preuve.png',
                'mimetype': 'image/png',
                'url': '/web/content/44',
                'download_url': '/web/content/44?download=true',
                'proof_data': proofData,
              },
            ],
            'lines': [
              {
                'id': 92,
                'carnet_type_id': 7,
                'carnet_type_code': 'C1-1000',
                'carnet_type_name': 'Carnet 1 × 1000',
                'carnet_qty': 1,
                'face_count': 1,
                'face_value': 1000,
                'amount_total': 1000,
              },
            ],
          },
        },
        clientId: 'user-1',
        clientName: 'Client Test',
        companyId: '1',
        requestedPurchaseId: 18,
      );

      expect(lot.paymentReference, 'PAY-18');
      expect(lot.proofs, hasLength(1));
      expect(lot.proofs.first.filename, 'preuve.png');
      expect(lot.proofs.first.bytes, isNotNull);
      expect(lot.proofs.first.hasImagePreview, isTrue);
    });

    test(
      'decodes mobile purchase list inline proof data for image preview',
      () {
        final proofData = base64Encode([
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          ...utf8.encode('proof-list'),
        ]);

        final lots = AcpecPurchasesMapper.fromRpcResult(
          {
            'data': {
              'items': [
                {
                  'id': 19,
                  'name': 'ACH/2026/00019',
                  'public_code': 'PUR-19',
                  'state': 'submitted',
                  'amount_total': 1000,
                  'face_qty_total': 1,
                  'proof_attachments': [
                    {
                      'id': 45,
                      'filename': 'preuve-liste.png',
                      'mimetype': 'image/png',
                      'url': '/web/content/45',
                      'proof_image_data': proofData,
                    },
                  ],
                  'lines': [
                    {
                      'id': 93,
                      'carnet_type_id': 7,
                      'carnet_type_code': 'C1-1000',
                      'carnet_type_name': 'Carnet 1 × 1000',
                      'carnet_qty': 1,
                      'face_count': 1,
                      'face_value': 1000,
                      'amount_total': 1000,
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
        expect(lots.first.proofs, hasLength(1));
        expect(lots.first.proofs.first.filename, 'preuve-liste.png');
        expect(lots.first.proofs.first.bytes, isNotNull);
        expect(lots.first.proofs.first.hasImagePreview, isTrue);
      },
    );
  });
}
