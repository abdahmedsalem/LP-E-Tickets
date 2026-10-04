import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/domain/models/transfer_inventory.dart';
import 'package:fueltoken_app/features/transfer/logic/transfer_carnets_logic.dart';

void main() {
  TransferInventoryItem buildFaceLine({
    required int initialQty,
    required int availableQty,
    required DateTime expirationDate,
  }) {
    return TransferInventoryItem(
      id: 'fl-1',
      carnetTypeId: 'ct-1',
      carnetTypeCode: 'C10-1000',
      carnetTypeName: 'Carnet 10 x 1000',
      carnetNo: 'ACH/2026/00001',
      carnetShortCode: '00001',
      carnetFaceCount: 12,
      faceValue: 1000,
      initialQty: initialQty,
      availableQty: availableQty,
      qrActiveQty: 0,
      qrBlockedQty: 0,
      consumedQty: 0,
      expiredQty: 0,
      expirationDate: expirationDate,
    );
  }

  test('filters only intact face lines with at least one full carnet', () {
    final intact = buildFaceLine(
      initialQty: 12,
      availableQty: 12,
      expirationDate: DateTime.now().add(const Duration(days: 10)),
    );
    final partial = buildFaceLine(
      initialQty: 12,
      availableQty: 8,
      expirationDate: DateTime.now().add(const Duration(days: 10)),
    );
    final expired = buildFaceLine(
      initialQty: 12,
      availableQty: 12,
      expirationDate: DateTime.now().subtract(const Duration(days: 1)),
    );

    expect(isTransferableCarnetLine(intact, 4), isTrue);
    expect(transferableCarnetCount(intact, 4), 3);

    expect(isTransferableCarnetLine(partial, 4), isFalse);
    expect(transferableCarnetCount(partial, 4), 0);

    expect(isTransferableCarnetLine(expired, 4), isFalse);
    expect(transferableCarnetCount(expired, 4), 0);
  });

  test('rejects lines attached to any qr state or consumption state', () {
    final qrActive = buildFaceLine(
      initialQty: 12,
      availableQty: 12,
      expirationDate: DateTime.now().add(const Duration(days: 10)),
    );
    final qrBlocked = buildFaceLine(
      initialQty: 12,
      availableQty: 12,
      expirationDate: DateTime.now().add(const Duration(days: 10)),
    );
    final consumed = buildFaceLine(
      initialQty: 12,
      availableQty: 12,
      expirationDate: DateTime.now().add(const Duration(days: 10)),
    );
    final expiredQty = buildFaceLine(
      initialQty: 12,
      availableQty: 12,
      expirationDate: DateTime.now().add(const Duration(days: 10)),
    );

    expect(isTransferableCarnetLine(qrActive, 4), isTrue);

    final qrActiveLine = TransferInventoryItem(
      id: qrActive.id,
      carnetTypeId: qrActive.carnetTypeId,
      carnetTypeCode: qrActive.carnetTypeCode,
      carnetTypeName: qrActive.carnetTypeName,
      carnetNo: qrActive.carnetNo,
      carnetShortCode: qrActive.carnetShortCode,
      carnetFaceCount: qrActive.carnetFaceCount,
      faceValue: qrActive.faceValue,
      initialQty: qrActive.initialQty,
      availableQty: qrActive.availableQty,
      qrActiveQty: 1,
      qrBlockedQty: 0,
      consumedQty: 0,
      expiredQty: 0,
      expirationDate: qrActive.expirationDate,
    );
    final qrBlockedLine = TransferInventoryItem(
      id: qrBlocked.id,
      carnetTypeId: qrBlocked.carnetTypeId,
      carnetTypeCode: qrBlocked.carnetTypeCode,
      carnetTypeName: qrBlocked.carnetTypeName,
      carnetNo: qrBlocked.carnetNo,
      carnetShortCode: qrBlocked.carnetShortCode,
      carnetFaceCount: qrBlocked.carnetFaceCount,
      faceValue: qrBlocked.faceValue,
      initialQty: qrBlocked.initialQty,
      availableQty: qrBlocked.availableQty,
      qrActiveQty: 0,
      qrBlockedQty: 1,
      consumedQty: 0,
      expiredQty: 0,
      expirationDate: qrBlocked.expirationDate,
    );
    final consumedLine = TransferInventoryItem(
      id: consumed.id,
      carnetTypeId: consumed.carnetTypeId,
      carnetTypeCode: consumed.carnetTypeCode,
      carnetTypeName: consumed.carnetTypeName,
      carnetNo: consumed.carnetNo,
      carnetShortCode: consumed.carnetShortCode,
      carnetFaceCount: consumed.carnetFaceCount,
      faceValue: consumed.faceValue,
      initialQty: consumed.initialQty,
      availableQty: consumed.availableQty,
      qrActiveQty: 0,
      qrBlockedQty: 0,
      consumedQty: 1,
      expiredQty: 0,
      expirationDate: consumed.expirationDate,
    );
    final expiredQtyLine = TransferInventoryItem(
      id: expiredQty.id,
      carnetTypeId: expiredQty.carnetTypeId,
      carnetTypeCode: expiredQty.carnetTypeCode,
      carnetTypeName: expiredQty.carnetTypeName,
      carnetNo: expiredQty.carnetNo,
      carnetShortCode: expiredQty.carnetShortCode,
      carnetFaceCount: expiredQty.carnetFaceCount,
      faceValue: expiredQty.faceValue,
      initialQty: expiredQty.initialQty,
      availableQty: expiredQty.availableQty,
      qrActiveQty: 0,
      qrBlockedQty: 0,
      consumedQty: 0,
      expiredQty: 1,
      expirationDate: expiredQty.expirationDate,
    );

    expect(isTransferableCarnetLine(qrActiveLine, 4), isFalse);
    expect(isTransferableCarnetLine(qrBlockedLine, 4), isFalse);
    expect(isTransferableCarnetLine(consumedLine, 4), isFalse);
    expect(isTransferableCarnetLine(expiredQtyLine, 4), isFalse);
  });

  test('rejects face lines without a complete carnet', () {
    final line = buildFaceLine(
      initialQty: 3,
      availableQty: 3,
      expirationDate: DateTime.now().add(const Duration(days: 10)),
    );

    expect(isTransferableCarnetLine(line, 4), isFalse);
    expect(transferableCarnetCount(line, 4), 0);
  });
}
