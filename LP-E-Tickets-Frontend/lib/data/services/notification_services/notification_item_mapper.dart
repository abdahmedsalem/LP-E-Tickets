import '../../../domain/models/notifications/notification_item.dart';

class NotificationItemMapper {
  static NotificationItem fromJson(Map<String, dynamic> json) {
    List<T> readList<T>(String key, T Function(Map<String, dynamic>) map) =>
        (json[key] as List?)
            ?.whereType<Map>()
            .map((value) => map(Map<String, dynamic>.from(value)))
            .toList() ??
        const [];

    return NotificationItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      timeLabel: json['timeLabel']?.toString() ?? '',
      notificationDateLabel: json['notificationDateLabel']?.toString(),
      category: json['category']?.toString(),
      purchaseStatus: json['purchaseStatus']?.toString(),
      amountLabel: json['amountLabel']?.toString(),
      validationDateLabel: json['validationDateLabel']?.toString(),
      rejectionReason: json['rejectionReason']?.toString(),
      purchaseLines: readList(
        'purchaseLines',
        NotificationItemMapper._purchaseLineFromJson,
      ),
      transferLines: readList(
        'transferLines',
        NotificationItemMapper._purchaseLineFromJson,
      ),
      transferPartyPhone: json['transferPartyPhone']?.toString(),
      qrPublicCode: json['qrPublicCode']?.toString(),
      qrExpirationLines: readList(
        'qrExpirationLines',
        NotificationItemMapper._qrExpirationLineFromJson,
      ),
      actionLabel: json['actionLabel']?.toString(),
      actionRoute: json['actionRoute']?.toString(),
      read: json['read'] == true,
    );
  }

  static Map<String, dynamic> toJson(NotificationItem item) => {
    'id': item.id,
    'title': item.title,
    'body': item.body,
    'timeLabel': item.timeLabel,
    'notificationDateLabel': item.notificationDateLabel,
    'category': item.category,
    'purchaseStatus': item.purchaseStatus,
    'amountLabel': item.amountLabel,
    'validationDateLabel': item.validationDateLabel,
    'rejectionReason': item.rejectionReason,
    'purchaseLines': item.purchaseLines.map(_purchaseLineToJson).toList(),
    'transferLines': item.transferLines.map(_purchaseLineToJson).toList(),
    'transferPartyPhone': item.transferPartyPhone,
    'qrExpirationLines': item.qrExpirationLines
        .map(_qrExpirationLineToJson)
        .toList(),
    'qrPublicCode': item.qrPublicCode,
    'actionLabel': item.actionLabel,
    'actionRoute': item.actionRoute,
    'read': item.read,
  };

  static NotificationPurchaseLineItem _purchaseLineFromJson(
    Map<String, dynamic> json,
  ) => NotificationPurchaseLineItem(
    label: json['label']?.toString() ?? '',
    quantityLabel: json['quantityLabel']?.toString() ?? '',
    amountLabel: json['amountLabel']?.toString() ?? '',
    faceValue: (json['faceValue'] as num?)?.toInt() ?? 0,
    carnetSize: (json['carnetSize'] as num?)?.toInt() ?? 0,
    carnetCount: (json['carnetCount'] as num?)?.toInt() ?? 0,
  );

  static Map<String, dynamic> _purchaseLineToJson(
    NotificationPurchaseLineItem item,
  ) => {
    'label': item.label,
    'quantityLabel': item.quantityLabel,
    'amountLabel': item.amountLabel,
    'faceValue': item.faceValue,
    'carnetSize': item.carnetSize,
    'carnetCount': item.carnetCount,
  };

  static NotificationQrExpirationLineItem _qrExpirationLineFromJson(
    Map<String, dynamic> json,
  ) => NotificationQrExpirationLineItem(
    faceValue: (json['faceValue'] as num?)?.toInt() ?? 0,
    quantityLabel: json['quantityLabel']?.toString() ?? '',
    expirationLabel: json['expirationLabel']?.toString(),
    lotLabel: json['lotLabel']?.toString(),
  );

  static Map<String, dynamic> _qrExpirationLineToJson(
    NotificationQrExpirationLineItem item,
  ) => {
    'faceValue': item.faceValue,
    'quantityLabel': item.quantityLabel,
    'expirationLabel': item.expirationLabel,
    'lotLabel': item.lotLabel,
  };
}
