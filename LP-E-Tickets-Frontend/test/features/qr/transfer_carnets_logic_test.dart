import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/features/transfer/logic/transfer_carnets_logic.dart';
import 'package:fueltoken_app/features/transfer/models/transfer_inventory.dart';

void main() {
  TransferInventoryItem buildItem({
    int initialQty = 12,
    int availableQty = 12,
    int qrActiveQty = 0,
    int qrBlockedQty = 0,
    int consumedQty = 0,
    int expiredQty = 0,
    DateTime? expirationDate,
  }) {
    return TransferInventoryItem(
      id: 'fl-1',
      carnetTypeId: 'ct-1',
      carnetTypeCode: 'C10-1000',
      carnetTypeName: 'Carnet 10 x 1000',
      carnetNo: '',
      carnetShortCode: '',
      carnetFaceCount: 0,
      faceValue: 1000,
      initialQty: initialQty,
      availableQty: availableQty,
      qrActiveQty: qrActiveQty,
      qrBlockedQty: qrBlockedQty,
      consumedQty: consumedQty,
      expiredQty: expiredQty,
      expirationDate:
          expirationDate ??
          DateTime.now().toUtc().add(const Duration(days: 10)),
    );
  }

  test('filters only intact face lines with at least one full carnet', () {
    final intact = buildItem();
    final partial = buildItem(availableQty: 8);
    final expired = buildItem(
      expirationDate: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    );

    expect(isTransferableCarnetLine(intact, 4), isTrue);
    expect(transferableCarnetCount(intact, 4), 3);
    expect(isTransferableCarnetLine(partial, 4), isFalse);
    expect(transferableCarnetCount(partial, 4), 0);
    expect(isTransferableCarnetLine(expired, 4), isFalse);
    expect(transferableCarnetCount(expired, 4), 0);
  });

  test('rejects lines attached to any qr state or consumption state', () {
    expect(isTransferableCarnetLine(buildItem(qrActiveQty: 1), 4), isFalse);
    expect(isTransferableCarnetLine(buildItem(qrBlockedQty: 1), 4), isFalse);
    expect(isTransferableCarnetLine(buildItem(consumedQty: 1), 4), isFalse);
    expect(isTransferableCarnetLine(buildItem(expiredQty: 1), 4), isFalse);
  });

  test('rejects lines without a complete carnet size', () {
    final line = buildItem(initialQty: 3, availableQty: 3);

    expect(isTransferableCarnetLine(line, 4), isFalse);
    expect(transferableCarnetCount(line, 4), 0);
  });
}
