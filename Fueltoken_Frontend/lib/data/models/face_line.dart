import 'package:equatable/equatable.dart';

/// acpec.fuel.face.line — aggregated face line per (lot, ticket type, face value).
/// Conservation invariant:
///   initialQty = availableQty + qrActiveQty + qrBlockedQty + consumedQty + expiredQty
class FaceLine extends Equatable {
  final String id;
  final String lotId;
  final String lotInternalRef;
  final String purchaseLineId;
  final String carnetTypeId;
  final String carnetTypeCode;
  final String carnetTypeName;
  final int carnetFaceCount;
  final int faceValue;
  final int initialQty;
  final int availableQty;
  final int qrActiveQty;
  final int qrBlockedQty;
  final int consumedQty;
  final int expiredQty;
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
    this.carnetFaceCount = 0,
    required this.faceValue,
    required this.initialQty,
    required this.availableQty,
    required this.qrActiveQty,
    required this.qrBlockedQty,
    required this.consumedQty,
    required this.expiredQty,
    required this.expirationDate,
    required this.ownerId,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expirationDate);
  int get availableValue => availableQty * faceValue;
  int get expiredValue => expiredQty * faceValue;

  bool get conservationOk =>
      initialQty ==
      availableQty + qrActiveQty + qrBlockedQty + consumedQty + expiredQty;

  FaceLine copyWith({
    int? availableQty,
    int? qrActiveQty,
    int? qrBlockedQty,
    int? consumedQty,
    int? expiredQty,
  }) {
    return FaceLine(
      id: id,
      lotId: lotId,
      lotInternalRef: lotInternalRef,
      purchaseLineId: purchaseLineId,
      carnetTypeId: carnetTypeId,
      carnetTypeCode: carnetTypeCode,
      carnetTypeName: carnetTypeName,
      carnetFaceCount: carnetFaceCount,
      faceValue: faceValue,
      initialQty: initialQty,
      availableQty: availableQty ?? this.availableQty,
      qrActiveQty: qrActiveQty ?? this.qrActiveQty,
      qrBlockedQty: qrBlockedQty ?? this.qrBlockedQty,
      consumedQty: consumedQty ?? this.consumedQty,
      expiredQty: expiredQty ?? this.expiredQty,
      expirationDate: expirationDate,
      ownerId: ownerId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    lotId,
    faceValue,
    carnetFaceCount,
    initialQty,
    availableQty,
    qrActiveQty,
    qrBlockedQty,
    consumedQty,
    expiredQty,
  ];
}
