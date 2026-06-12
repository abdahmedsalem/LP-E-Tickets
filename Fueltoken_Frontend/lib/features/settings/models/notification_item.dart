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

  /// Valeur unitaire d'un ticket (ex. 2000 MRU).
  final int faceValue;

  /// Nombre de tickets par carnet (ex. 10).
  final int carnetSize;

  /// Nombre de carnets commandés.
  final int carnetCount;

  int get totalFaces => carnetCount * carnetSize;
  int get totalAmount => totalFaces * faceValue;

  factory NotificationPurchaseLineItem.fromJson(Map<String, dynamic> json) {
    return NotificationPurchaseLineItem(
      label: json['label']?.toString() ?? '',
      quantityLabel: json['quantityLabel']?.toString() ?? '',
      amountLabel: json['amountLabel']?.toString() ?? '',
      faceValue: (json['faceValue'] as num?)?.toInt() ?? 0,
      carnetSize: (json['carnetSize'] as num?)?.toInt() ?? 0,
      carnetCount: (json['carnetCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'quantityLabel': quantityLabel,
      'amountLabel': amountLabel,
      'faceValue': faceValue,
      'carnetSize': carnetSize,
      'carnetCount': carnetCount,
    };
  }
}

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timeLabel,
    this.category,
    this.purchaseStatus,
    this.amountLabel,
    this.validationDateLabel,
    this.rejectionReason,
    this.purchaseLines = const [],
    this.actionLabel,
    this.actionRoute,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final String timeLabel;
  final String? category;
  final String? purchaseStatus;
  final String? amountLabel;
  final String? validationDateLabel;
  final String? rejectionReason;
  final List<NotificationPurchaseLineItem> purchaseLines;
  final String? actionLabel;
  final String? actionRoute;
  bool read;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      timeLabel: json['timeLabel']?.toString() ?? '',
      category: json['category']?.toString(),
      purchaseStatus: json['purchaseStatus']?.toString(),
      amountLabel: json['amountLabel']?.toString(),
      validationDateLabel: json['validationDateLabel']?.toString(),
      rejectionReason: json['rejectionReason']?.toString(),
      purchaseLines:
          (json['purchaseLines'] as List?)
              ?.whereType<Map>()
              .map(
                (e) => NotificationPurchaseLineItem.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList() ??
          const [],
      actionLabel: json['actionLabel']?.toString(),
      actionRoute: json['actionRoute']?.toString(),
      read: json['read'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'timeLabel': timeLabel,
      'category': category,
      'purchaseStatus': purchaseStatus,
      'amountLabel': amountLabel,
      'validationDateLabel': validationDateLabel,
      'rejectionReason': rejectionReason,
      'purchaseLines': purchaseLines.map((e) => e.toJson()).toList(),
      'actionLabel': actionLabel,
      'actionRoute': actionRoute,
      'read': read,
    };
  }
}
