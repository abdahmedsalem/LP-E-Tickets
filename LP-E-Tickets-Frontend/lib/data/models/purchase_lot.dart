import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../../core/utils/payment_proof.dart';

enum PurchaseLotState { draft, submitted, approved, rejected }

extension PurchaseLotStateX on PurchaseLotState {
  String get label {
    switch (this) {
      case PurchaseLotState.draft:
        return 'Brouillon';
      case PurchaseLotState.submitted:
        return 'Commande de carnets';
      case PurchaseLotState.approved:
        return 'Carnets achetés';
      case PurchaseLotState.rejected:
        return 'Commande de carnets rejetée';
    }
  }
}

/// acpec.fuel.purchase.line
class PurchaseLine extends Equatable {
  final String id;
  final String carnetTypeId;
  final String carnetTypeCode;
  final String carnetTypeName;
  final int carnetCount;
  final int carnetSize;
  final int faceValue;

  const PurchaseLine({
    required this.id,
    required this.carnetTypeId,
    required this.carnetTypeCode,
    required this.carnetTypeName,
    required this.carnetCount,
    required this.carnetSize,
    required this.faceValue,
  });

  int get faceCount => carnetCount * carnetSize;
  int get lineAmount => faceCount * faceValue;

  PurchaseLine copyWith({String? carnetTypeName}) {
    return PurchaseLine(
      id: id,
      carnetTypeId: carnetTypeId,
      carnetTypeCode: carnetTypeCode,
      carnetTypeName: carnetTypeName ?? this.carnetTypeName,
      carnetCount: carnetCount,
      carnetSize: carnetSize,
      faceValue: faceValue,
    );
  }

  @override
  List<Object?> get props => [
    id,
    carnetTypeId,
    carnetTypeCode,
    carnetTypeName,
    carnetCount,
    carnetSize,
    faceValue,
  ];
}

/// Preuve ou pièce jointe liée à une commande de carnets (détail Odoo).
class PurchaseProofSummary extends Equatable {
  const PurchaseProofSummary({
    required this.label,
    this.filename,
    this.url,
    this.mimeType,
    this.uploadedAt,
    this.bytes,
  });

  final String label;
  final String? filename;
  final String? url;
  final String? mimeType;
  final DateTime? uploadedAt;
  final Uint8List? bytes;

  bool get hasImagePreview {
    if (bytes != null && bytes!.isNotEmpty) {
      if (_looksLikeImageBytes(bytes!)) {
        return true;
      }
      final imageLike =
          isImageMimeType(mimeType, filename: filename) ||
          looksLikeImageFilename(filename);
      return mimeType == null || imageLike;
    }
    final imageLike =
        isImageMimeType(mimeType, filename: filename) ||
        looksLikeImageFilename(filename);
    if (url != null && url!.isNotEmpty) {
      return imageLike;
    }
    return false;
  }

  static bool _looksLikeImageBytes(Uint8List bytes) {
    if (bytes.length < 3) {
      return false;
    }
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }
    // PNG: 89 50 4E 47
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    // GIF: GIF
    if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return true;
    }
    // WEBP: WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  bool get isDisplayable =>
      (bytes != null && bytes!.isNotEmpty) ||
      (url != null && url!.isNotEmpty) ||
      looksLikeAttachmentFilename(filename);

  PurchaseProofSummary copyWith({
    String? label,
    String? filename,
    String? url,
    String? mimeType,
    DateTime? uploadedAt,
    Uint8List? bytes,
  }) {
    return PurchaseProofSummary(
      label: label ?? this.label,
      filename: filename ?? this.filename,
      url: url ?? this.url,
      mimeType: mimeType ?? this.mimeType,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      bytes: bytes ?? this.bytes,
    );
  }

  @override
  List<Object?> get props => [
    label,
    filename,
    url,
    mimeType,
    uploadedAt,
    bytes,
  ];
}

/// acpec.fuel.purchase
class PurchaseLot extends Equatable {
  final String id;
  final String internalRef;
  final String publicCode;
  final String clientId;
  final String clientName;
  final String companyId;
  final String? paymentProofPath;
  final String? paymentReference;
  final List<PurchaseProofSummary> proofs;
  final List<PurchaseLine> lines;
  final PurchaseLotState state;
  final String? validatorId;
  final String? validatorName;
  final DateTime? submittedAt;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime? validationDate;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime expirationDate;

  const PurchaseLot({
    required this.id,
    required this.internalRef,
    required this.publicCode,
    required this.clientId,
    required this.clientName,
    required this.companyId,
    this.paymentProofPath,
    this.paymentReference,
    this.proofs = const [],
    required this.lines,
    required this.state,
    this.validatorId,
    this.validatorName,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.validationDate,
    this.rejectionReason,
    required this.createdAt,
    required this.expirationDate,
  });

  int get totalAmount => lines.fold(0, (sum, line) => sum + line.lineAmount);

  int get totalFaces => lines.fold(0, (sum, line) => sum + line.faceCount);

  PurchaseLot copyWith({
    PurchaseLotState? state,
    String? validatorId,
    String? validatorName,
    DateTime? submittedAt,
    DateTime? approvedAt,
    DateTime? rejectedAt,
    DateTime? validationDate,
    String? rejectionReason,
    String? paymentProofPath,
    String? paymentReference,
    List<PurchaseProofSummary>? proofs,
    List<PurchaseLine>? lines,
  }) {
    return PurchaseLot(
      id: id,
      internalRef: internalRef,
      publicCode: publicCode,
      clientId: clientId,
      clientName: clientName,
      companyId: companyId,
      paymentProofPath: paymentProofPath ?? this.paymentProofPath,
      paymentReference: paymentReference ?? this.paymentReference,
      proofs: proofs ?? this.proofs,
      lines: lines ?? this.lines,
      state: state ?? this.state,
      validatorId: validatorId ?? this.validatorId,
      validatorName: validatorName ?? this.validatorName,
      submittedAt: submittedAt ?? this.submittedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      validationDate: validationDate ?? this.validationDate,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt,
      expirationDate: expirationDate,
    );
  }

  @override
  List<Object?> get props => [
    id,
    internalRef,
    publicCode,
    state,
    lines,
    proofs,
    rejectionReason,
  ];
}
