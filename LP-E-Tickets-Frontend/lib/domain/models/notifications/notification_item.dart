class NotificationPurchaseLineItem {
  const NotificationPurchaseLineItem({
    required this.label,
    required this.quantityLabel,
    required this.amountLabel,
    this.faceValue = 0,
    this.carnetSize = 0,
    this.carnetCount = 0,
  });

  final String label;
  final String quantityLabel;
  final String amountLabel;

  /// Valeur unitaire d'un ticket.
  final int faceValue;

  /// Nombre de tickets par carnet (ex. 10).
  final int carnetSize;

  /// Nombre de carnets commandés.
  final int carnetCount;

  int get totalFaces => carnetCount * carnetSize;
  int get totalAmount => totalFaces * faceValue;
}

class NotificationQrExpirationLineItem {
  const NotificationQrExpirationLineItem({
    required this.faceValue,
    required this.quantityLabel,
    this.expirationLabel,
    this.lotLabel,
  });

  final int faceValue;
  final String quantityLabel;
  final String? expirationLabel;
  final String? lotLabel;
}

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timeLabel,
    this.notificationDateLabel,
    this.category,
    this.purchaseStatus,
    this.amountLabel,
    this.validationDateLabel,
    this.rejectionReason,
    this.purchaseLines = const [],
    this.transferLines = const [],
    this.transferPartyPhone,
    this.qrExpirationLines = const [],
    this.qrPublicCode,
    this.actionLabel,
    this.actionRoute,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final String timeLabel;
  final String? notificationDateLabel;
  final String? category;
  final String? purchaseStatus;
  final String? amountLabel;
  final String? validationDateLabel;
  final String? rejectionReason;
  final List<NotificationPurchaseLineItem> purchaseLines;
  final List<NotificationPurchaseLineItem> transferLines;
  final String? transferPartyPhone;
  final List<NotificationQrExpirationLineItem> qrExpirationLines;
  final String? qrPublicCode;
  final String? actionLabel;
  final String? actionRoute;
  bool read;
}
