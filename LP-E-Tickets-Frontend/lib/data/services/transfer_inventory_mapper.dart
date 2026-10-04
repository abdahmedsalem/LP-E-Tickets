import '../../domain/models/portfolio/face_line.dart';
import '../../domain/models/purchase/carnet_type.dart';
import '../../domain/models/transfer_inventory.dart';

/// Maps ACPEC/data catalogue models to the transfer domain model.
class TransferInventoryMapper {
  const TransferInventoryMapper._();

  static TransferInventoryCatalog fromData({
    required List<CarnetType> types,
    required List<FaceLine> faces,
  }) {
    return TransferInventoryCatalog(
      types: types.map(_mapCarnetType).toList(growable: false),
      faces: faces.map(_mapFaceLine).toList(growable: false),
    );
  }

  static TransferCarnetType _mapCarnetType(CarnetType type) {
    return TransferCarnetType(
      id: type.id,
      code: type.code,
      name: type.name,
      size: type.size,
    );
  }

  static TransferInventoryItem _mapFaceLine(FaceLine line) {
    return TransferInventoryItem(
      id: line.id,
      carnetTypeId: line.carnetTypeId,
      carnetTypeCode: line.carnetTypeCode,
      carnetTypeName: line.carnetTypeName,
      carnetNo: line.carnetNo,
      carnetShortCode: line.carnetShortCode,
      carnetFaceCount: line.carnetFaceCount,
      faceValue: line.faceValue,
      initialQty: line.initialQty,
      availableQty: line.availableQty,
      qrActiveQty: line.qrActiveQty,
      qrBlockedQty: line.qrBlockedQty,
      consumedQty: line.consumedQty,
      expiredQty: line.expiredQty,
      expirationDate: line.expirationDate,
    );
  }
}
