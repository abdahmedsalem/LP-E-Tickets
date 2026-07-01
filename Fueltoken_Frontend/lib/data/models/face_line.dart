import 'package:equatable/equatable.dart';

/// acpec.fuel.face.line — carnet individualisé disponible côté mobile.
///
/// Doctrine backend Patch34A+ :
///   1 face_line = 1 carnet.
/// `id` doit correspondre à `face_line_id` quand il est fourni par l'API.
class FaceLine extends Equatable {
  final String id;
  final String lotId;
  final String lotInternalRef;
  final String purchaseLineId;
  final String carnetTypeId;
  final String carnetTypeCode;
  final String carnetTypeName;
  final String carnetNo;
  final String lotShortCode;
  final String carnetShortCode;
  final int carnetSequence;
  final int carnetFaceCount;
  final int faceValue;
  final int initialQty;
  final int availableQty;
  final int qrActiveQty;
  final int qrBlockedQty;
  final int consumedQty;
  final int expiredQty;
  final int transferredOutQty;
  final DateTime expirationDate;
  final String ownerId;

  const FaceLine({
    required this.id,
    required this.lotId,
    required this.lotInternalRef,
    required this.purchaseLineId,
    required this.carnetTypeId,
    required this.carnetTypeCode,
    this.carnetTypeName = '',
    this.carnetNo = '',
    this.lotShortCode = '',
    this.carnetShortCode = '',
    this.carnetSequence = 0,
    this.carnetFaceCount = 0,
    required this.faceValue,
    required this.initialQty,
    required this.availableQty,
    required this.qrActiveQty,
    required this.qrBlockedQty,
    required this.consumedQty,
    required this.expiredQty,
    this.transferredOutQty = 0,
    required this.expirationDate,
    required this.ownerId,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expirationDate);
  int get availableValue => availableQty * faceValue;
  int get expiredValue => expiredQty * faceValue;

  bool get conservationOk =>
      initialQty ==
      availableQty +
          qrActiveQty +
          qrBlockedQty +
          consumedQty +
          expiredQty +
          transferredOutQty;

  FaceLine copyWith({
    int? availableQty,
    int? qrActiveQty,
    int? qrBlockedQty,
    int? consumedQty,
    int? expiredQty,
    int? transferredOutQty,
  }) {
    return FaceLine(
      id: id,
      lotId: lotId,
      lotInternalRef: lotInternalRef,
      purchaseLineId: purchaseLineId,
      carnetTypeId: carnetTypeId,
      carnetTypeCode: carnetTypeCode,
      carnetTypeName: carnetTypeName,
      carnetNo: carnetNo,
      lotShortCode: lotShortCode,
      carnetShortCode: carnetShortCode,
      carnetSequence: carnetSequence,
      carnetFaceCount: carnetFaceCount,
      faceValue: faceValue,
      initialQty: initialQty,
      availableQty: availableQty ?? this.availableQty,
      qrActiveQty: qrActiveQty ?? this.qrActiveQty,
      qrBlockedQty: qrBlockedQty ?? this.qrBlockedQty,
      consumedQty: consumedQty ?? this.consumedQty,
      expiredQty: expiredQty ?? this.expiredQty,
      transferredOutQty: transferredOutQty ?? this.transferredOutQty,
      expirationDate: expirationDate,
      ownerId: ownerId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    lotId,
    purchaseLineId,
    carnetTypeId,
    carnetTypeCode,
    carnetTypeName,
    carnetNo,
    lotShortCode,
    carnetShortCode,
    carnetSequence,
    faceValue,
    carnetFaceCount,
    initialQty,
    availableQty,
    qrActiveQty,
    qrBlockedQty,
    consumedQty,
    expiredQty,
    transferredOutQty,
  ];
}
