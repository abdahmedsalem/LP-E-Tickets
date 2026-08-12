import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/models/business_transaction.dart';
import 'package:fueltoken_app/data/models/carnet_type.dart';
import 'package:fueltoken_app/data/models/face_line.dart';
import 'package:fueltoken_app/data/models/purchase_lot.dart';
import 'package:fueltoken_app/data/models/qr_token.dart';
import 'package:fueltoken_app/data/services/acpec_carnet_catalog_service.dart';

void main() {
  group('AcpecCarnetCatalogService', () {
    const arabicName =
        '\u062f\u0641\u062a\u0631 - 10 \u062a\u0630\u0627\u0643\u0631';
    const types = [
      CarnetType(
        id: '7',
        code: 'C10-100',
        name: arabicName,
        size: 10,
        faceValue: 100,
        companyId: '1',
      ),
    ];

    test('applies localized carnet type names to face lines', () {
      final lines = [
        FaceLine(
          id: 'face-1',
          lotId: 'lot-1',
          lotInternalRef: 'LOT-1',
          purchaseLineId: 'line-1',
          carnetTypeId: '7',
          carnetTypeCode: 'C10-100',
          carnetTypeName: 'Carnet - 10 tickets x 100 MRU',
          carnetFaceCount: 10,
          faceValue: 100,
          initialQty: 10,
          availableQty: 10,
          qrActiveQty: 0,
          qrBlockedQty: 0,
          consumedQty: 0,
          expiredQty: 0,
          expirationDate: DateTime.utc(2027),
          ownerId: 'user-1',
        ),
      ];

      final localized =
          AcpecCarnetCatalogService.localizeFaceLinesByCarnetTypes(
            lines: lines,
            types: types,
          );

      expect(localized.single.carnetTypeName, arabicName);
    });

    test('applies localized carnet type names to QR lines', () {
      final qr = QrToken(
        id: 'qr-1',
        publicCode: 'PUB-1',
        ownerId: 'user-1',
        ownerName: 'Client',
        companyId: '1',
        state: QrState.active,
        lines: [
          QrLine(
            id: 'qr-line-1',
            qrId: 'qr-1',
            lotId: 'lot-1',
            lotInternalRef: 'LOT-1',
            faceLineId: 'face-1',
            carnetTypeId: '7',
            carnetTypeCode: 'C10-100',
            carnetTypeName: 'Carnet - 10 tickets x 100 MRU',
            carnetSize: 10,
            faceValue: 100,
            qty: 2,
            expirationDate: DateTime.utc(2027),
          ),
        ],
        createdAt: DateTime.utc(2026),
      );

      final localized = AcpecCarnetCatalogService.localizeQrTokenByCarnetTypes(
        qr: qr,
        types: types,
      );

      expect(localized.lines.single.carnetTypeName, arabicName);
    });

    test('applies localized carnet type names to transaction lines', () {
      final transactions = [
        BusinessTransaction(
          id: 'tx-1',
          type: TxType.qrEmission,
          date: DateTime.utc(2026),
          userId: 'user-1',
          userName: 'Client',
          lines: const [
            TransactionLine(
              id: 'line-1',
              carnetTypeId: '7',
              carnetTypeCode: 'C10-100',
              carnetTypeName: 'Carnet - 10 tickets x 100 MRU',
              faceValue: 100,
              qty: 2,
              amount: 200,
              carnetSize: 10,
            ),
          ],
        ),
      ];

      final localized =
          AcpecCarnetCatalogService.localizeTransactionsByCarnetTypes(
            transactions: transactions,
            types: types,
          );

      expect(localized.single.lines.single.carnetTypeName, arabicName);
    });

    test('applies localized carnet type names to purchase lines', () {
      final lot = PurchaseLot(
        id: 'purchase-1',
        internalRef: 'PUR-1',
        publicCode: 'PUB-1',
        clientId: 'user-1',
        clientName: 'Client',
        companyId: '1',
        lines: const [
          PurchaseLine(
            id: 'line-1',
            carnetTypeId: '7',
            carnetTypeCode: 'C10-100',
            carnetTypeName: 'Carnet - 10 tickets x 100 MRU',
            carnetCount: 1,
            carnetSize: 10,
            faceValue: 100,
          ),
        ],
        state: PurchaseLotState.approved,
        createdAt: DateTime.utc(2026),
        expirationDate: DateTime.utc(2027),
      );

      final localized =
          AcpecCarnetCatalogService.localizePurchaseLotByCarnetTypes(
            lot: lot,
            types: types,
          );

      expect(localized.lines.single.carnetTypeName, arabicName);
    });

    test('matches carnet types by size and face value without id or code', () {
      final lines = const [
        PurchaseLine(
          id: 'line-1',
          carnetTypeId: '',
          carnetTypeCode: '',
          carnetTypeName: 'Carnet - 10 tickets x 100 MRU',
          carnetCount: 1,
          carnetSize: 10,
          faceValue: 100,
        ),
      ];

      final localized =
          AcpecCarnetCatalogService.localizePurchaseLinesByCarnetTypes(
            lines: lines,
            types: types,
          );

      expect(localized.single.carnetTypeName, arabicName);
    });

    test('applies localized carnet type names to wallet breakdown rows', () {
      final rows = [
        {
          'carnet_type_id': '7',
          'carnet_type_code': 'C10-100',
          'carnet_type_name': 'Carnet - 10 tickets x 100 MRU',
          'face_value': 100,
          'qty_available': 4,
        },
      ];

      final localized =
          AcpecCarnetCatalogService.localizeCarnetTypeBreakdownByCarnetTypes(
            value: rows,
            types: types,
          );

      expect(localized, isA<List<dynamic>>());
      expect(
        (localized as List<dynamic>).single['carnet_type_name'],
        arabicName,
      );
    });

    test('applies localized carnet type names to keyed wallet rows', () {
      final rowsByCode = {
        'C10-100': {
          'carnet_type_name': 'Carnet - 10 tickets x 100 MRU',
          'face_value': 100,
          'qty_available': 4,
        },
      };

      final localized =
          AcpecCarnetCatalogService.localizeCarnetTypeBreakdownByCarnetTypes(
            value: rowsByCode,
            types: types,
          );

      expect(localized, isA<Map<dynamic, dynamic>>());
      expect(
        (localized as Map<dynamic, dynamic>)['C10-100']['carnet_type_name'],
        arabicName,
      );
    });
  });
}
