import 'package:equatable/equatable.dart';

enum TxType {
  purchaseValidated,
  qrEmission,
  qrSplit,
  qrBlocked,
  stationConsumption,
  expiration,
  /// Mouvement générique renvoyé par l’API (hors types métier listés).
  walletLedger,
}

extension TxTypeX on TxType {
  /// Libellé technique (filtre uniquement côté client — l’API 5.6 n’accepte pas ce paramètre).
  String? get apiFilterValue {
    switch (this) {
      case TxType.purchaseValidated:
        return 'purchase_validated';
      case TxType.qrEmission:
        return 'qr_emission';
      case TxType.qrSplit:
        return 'qr_split';
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
      case TxType.purchaseValidated:
        return 'Lot validé';
      case TxType.qrEmission:
        return 'Émission QR';
      case TxType.qrSplit:
        return 'Split QR';
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
  });

  int get totalAmount => lines.fold(0, (s, l) => s + l.amount);

  @override
  List<Object?> get props => [id, type, date];
}
