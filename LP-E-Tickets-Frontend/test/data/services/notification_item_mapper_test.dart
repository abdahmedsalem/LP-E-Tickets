import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/notification_services/notification_item_mapper.dart';
import 'package:fueltoken_app/domain/models/notifications/notification_item.dart';

void main() {
  test('notification serialization stays in the data mapper', () {
    final item = NotificationItem(
      id: 'purchase-1',
      title: 'Achat validé',
      body: 'Votre achat est confirmé',
      timeLabel: '09:30',
      purchaseLines: const [
        NotificationPurchaseLineItem(
          label: 'K4',
          quantityLabel: '2 carnets',
          amountLabel: '4 000 UM',
          faceValue: 500,
          carnetSize: 4,
          carnetCount: 2,
        ),
      ],
      qrExpirationLines: const [
        NotificationQrExpirationLineItem(
          faceValue: 500,
          quantityLabel: '4 tickets',
          expirationLabel: '10/10/2026',
          lotLabel: 'LOT-1',
        ),
      ],
      read: true,
    );

    final restored = NotificationItemMapper.fromJson(
      NotificationItemMapper.toJson(item),
    );

    expect(restored.id, item.id);
    expect(restored.purchaseLines.single.carnetCount, 2);
    expect(restored.qrExpirationLines.single.lotLabel, 'LOT-1');
    expect(restored.read, isTrue);
  });
}
