/// Transfer catalogue exposed to the application and presentation layers.
class TransferInventoryCatalog {
  const TransferInventoryCatalog({required this.types, required this.faces});

  final List<TransferCarnetType> types;
  final List<TransferInventoryItem> faces;
}

class TransferCarnetType {
  const TransferCarnetType({
    required this.id,
    required this.code,
    required this.name,
    required this.size,
  });

  final String id;
  final String code;
  final String name;
  final int size;
}

class TransferInventoryItem {
  const TransferInventoryItem({
    required this.id,
    required this.carnetTypeId,
    required this.carnetTypeCode,
    required this.carnetTypeName,
    required this.carnetNo,
    required this.carnetShortCode,
    required this.carnetFaceCount,
    required this.faceValue,
    required this.initialQty,
    required this.availableQty,
    required this.qrActiveQty,
    required this.qrBlockedQty,
    required this.consumedQty,
    required this.expiredQty,
    required this.expirationDate,
  });

  final String id;
  final String carnetTypeId;
  final String carnetTypeCode;
  final String carnetTypeName;
  final String carnetNo;
  final String carnetShortCode;
  final int carnetFaceCount;
  final int faceValue;
  final int initialQty;
  final int availableQty;
  final int qrActiveQty;
  final int qrBlockedQty;
  final int consumedQty;
  final int expiredQty;
  final DateTime expirationDate;

  bool get isExpired => DateTime.now().toUtc().isAfter(expirationDate);
}
