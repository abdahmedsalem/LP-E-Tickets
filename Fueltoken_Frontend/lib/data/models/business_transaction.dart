import 'package:equatable/equatable.dart';

enum TxType {
  purchaseSubmitted,
  purchaseValidated,
  purchaseRejected,
  qrEmission,
  qrSeparer,
  qrRetirer,
  carnetTransfer,
  carnetReceived,
  qrBlocked,
  stationConsumption,
  expiration,
  /// Mouvement générique renvoyé par l'API (hors types métier listés).
  walletLedger,
}

extension TxTypeX on TxType {
  String? get apiFilterValue {
    switch (this) {
      case TxType.purchaseSubmitted:
        return 'purchase_submitted';
      case TxType.purchaseValidated:
        return 'purchase_validated';
      case TxType.purchaseRejected:
        return 'purchase_rejected';
      case TxType.qrEmission:
        return 'qr_emission';
      case TxType.qrSeparer:
        return 'separer_qr';
      case TxType.qrRetirer:
        return 'qr_retirer';
      case TxType.carnetTransfer:
        return 'carnet_transfer';
      case TxType.carnetReceived:
        return 'carnet_received';
      case TxType.qrBlocked:
        return 'qr_blocked';
      case TxType.stationConsumption:
        return 'station_consumption';
      case TxType.expiration:
        return 'expiration';
      case TxType.walletLedger:
        return null;
    }
  }

  String get label {
    switch (this) {
      case TxType.purchaseSubmitted:
        return 'Achat en attente';
      case TxType.purchaseValidated:
        return 'Achat validé';
      case TxType.purchaseRejected:
        return 'Achat rejeté';
      case TxType.qrEmission:
        return 'Émission QR';
      case TxType.qrSeparer:
        return 'Séparation QR';
      case TxType.qrRetirer:
        return 'Retrait QR';
      case TxType.carnetTransfer:
        return 'Transfert de carnets';
      case TxType.carnetReceived:
        return 'Réception de carnets';
      case TxType.qrBlocked:
        return 'QR bloqué';
      case TxType.stationConsumption:
        return 'Consommation station';
      case TxType.expiration:
        return 'Expiration';
      case TxType.walletLedger:
        return 'Opération';
    }
  }

  bool get isTransfer =>
      this == TxType.carnetTransfer || this == TxType.carnetReceived;
}

class TransactionLine extends Equatable {
  final String id;
  final int faceValue;
  final int qty;
  final int amount;
  final String? lotId;
  final String? faceLineId;
  final String? qrId;

  const TransactionLine({
    required this.id,
    required this.faceValue,
    required this.qty,
    required this.amount,
    this.lotId,
    this.faceLineId,
    this.qrId,
  });

  @override
  List<Object?> get props => [id, faceValue, qty, amount];
}

/// acpec.fuel.transaction
class BusinessTransaction extends Equatable {
  final String id;
  final TxType type;
  final DateTime date;
  final String? lotId;
  final String? lotInternalRef;
  final String? qrId;
  final String? qrPublicCode;
  final String? stationId;
  final String? stationName;
  final String userId;
  final String userName;
  final List<TransactionLine> lines;
  final String? note;

  /// Pour les transferts : nom de l'autre partie (destinataire si sortant, expéditeur si entrant).
  final String? transferParty;

  const BusinessTransaction({
    required this.id,
    required this.type,
    required this.date,
    required this.userId,
    required this.userName,
    required this.lines,
    this.lotId,
    this.lotInternalRef,
    this.qrId,
    this.qrPublicCode,
    this.stationId,
    this.stationName,
    this.note,
    this.transferParty,
  });

  int get totalAmount => lines.fold(0, (s, l) => s + l.amount);

  /// Libellé contextuel enrichi (avec partie pour les transferts).
  String get displayTitle {
    if (type == TxType.carnetTransfer && transferParty != null) {
      return 'Transfert vers $transferParty';
    }
    if (type == TxType.carnetReceived && transferParty != null) {
      return 'Reçu de $transferParty';
    }
    return type.label;
  }

  @override
  List<Object?> get props => [id, type, date];
}
