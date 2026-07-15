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
        return 'Commande en attente';
      case TxType.purchaseValidated:
        return 'Commande validée';
      case TxType.purchaseRejected:
        return 'Commande rejetée';
      case TxType.qrEmission:
        return 'Génération QR';
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
        return 'Consommation de carburant';
      case TxType.expiration:
        return 'Expiration QR';
      case TxType.walletLedger:
        return 'Opération';
    }
  }

  bool get isTransfer =>
      this == TxType.carnetTransfer || this == TxType.carnetReceived;
}

class TransactionLine extends Equatable {
  final String id;
  final String carnetTypeId;
  final String carnetTypeCode;
  final String carnetTypeName;
  final int faceValue;
  final int qty;
  final int amount;
  final int carnetSize;
  final DateTime? expirationDate;
  final String? lotId;
  final String? faceLineId;
  final String? qrId;

  const TransactionLine({
    required this.id,
    this.carnetTypeId = '',
    this.carnetTypeCode = '',
    this.carnetTypeName = '',
    required this.faceValue,
    required this.qty,
    required this.amount,
    this.carnetSize = 0,
    this.expirationDate,
    this.lotId,
    this.faceLineId,
    this.qrId,
  });

  @override
  List<Object?> get props => [
    id,
    carnetTypeId,
    carnetTypeCode,
    carnetTypeName,
    faceValue,
    qty,
    amount,
    carnetSize,
    expirationDate,
  ];
}

/// acpec.fuel.transaction
class BusinessTransaction extends Equatable {
  final String id;
  final String? txReference;
  final TxType type;
  final DateTime date;
  final String? lotId;
  final String? lotInternalRef;
  final String? qrId;
  final String? qrName;
  final String? qrPublicCode;
  final String? stationId;
  final String? stationName;
  final String userId;
  final String userName;
  final List<TransactionLine> lines;
  final String? note;
  final String? regularizationState;
  final String? regularizationReference;
  final DateTime? regularizationDate;
  final bool transferIsIncoming;
  final bool transferUsesTickets;
  final String? actorUserId;
  final String? counterpartyUserId;
  final String? actorUserName;
  final String? counterpartyUserName;

  /// Pour les transferts : nom de l'autre partie (destinataire si sortant, Expéditeur si entrant).
  final String? transferParty;

  /// Pour les transferts : numéro de téléphone de l'autre partie.
  final String? transferPartyPhone;

  const BusinessTransaction({
    required this.id,
    this.txReference,
    required this.type,
    required this.date,
    required this.userId,
    required this.userName,
    required this.lines,
    this.lotId,
    this.lotInternalRef,
    this.qrId,
    this.qrName,
    this.qrPublicCode,
    this.stationId,
    this.stationName,
    this.note,
    this.regularizationState,
    this.regularizationReference,
    this.regularizationDate,
    this.transferIsIncoming = false,
    this.transferUsesTickets = false,
    this.actorUserId,
    this.counterpartyUserId,
    this.actorUserName,
    this.counterpartyUserName,
    this.transferParty,
    this.transferPartyPhone,
  });

  int get totalAmount => lines.fold(0, (s, l) => s + l.amount);

  bool get hasTxReference => (txReference ?? '').trim().isNotEmpty;

  String get effectiveRegularizationState {
    final value = (regularizationState ?? '').trim().toLowerCase();
    return value.isEmpty || value == 'false' ? 'pending' : value;
  }

  bool get isRegularized => effectiveRegularizationState == 'regularized';

  String get regularizationLabel {
    switch (effectiveRegularizationState) {
      case 'regularized':
        return 'Régularisé';
      case 'pending':
        return 'Non régularisé';
      default:
        return effectiveRegularizationState;
    }
  }

  String get txNumber {
    final ref = (txReference ?? '').trim();
    return ref.isNotEmpty ? ref : id;
  }

  String get qrDisplayName {
    for (final value in [qrName, qrId, qrPublicCode]) {
      final s = (value ?? '').trim();
      if (s.isNotEmpty && s != 'false' && s != 'true') {
        return s;
      }
    }
    return '—';
  }

  bool get isTicketTransfer {
    if (type != TxType.carnetTransfer && type != TxType.carnetReceived) {
      return false;
    }
    if (transferUsesTickets) return true;
    if (lines.isEmpty) return false;
    return lines.every((line) => line.carnetSize <= 1);
  }

  String get transferKindLabel => isTicketTransfer ? 'tickets' : 'carnets';

  bool _matchesViewerAsCounterparty(String? viewerUserId) {
    final viewer = (viewerUserId ?? '').trim();
    if (viewer.isEmpty) return false;
    return (counterpartyUserId ?? '').trim() == viewer ||
        (counterpartyUserName ?? '').trim() == viewer;
  }

  bool _matchesViewerAsActor(String? viewerUserId) {
    final viewer = (viewerUserId ?? '').trim();
    if (viewer.isEmpty) return false;
    return (actorUserId ?? '').trim() == viewer ||
        (actorUserName ?? '').trim() == viewer;
  }

  bool isIncomingTransferForViewer(String? viewerUserId) {
    if (type != TxType.carnetTransfer && type != TxType.carnetReceived) {
      return false;
    }
    if (_matchesViewerAsCounterparty(viewerUserId)) return true;
    if (_matchesViewerAsActor(viewerUserId)) return false;
    return transferIsIncoming;
  }

  String transferPartyRoleLabelForViewer(String? viewerUserId) {
    return isIncomingTransferForViewer(viewerUserId)
        ? 'Expéditeur'
        : 'Bénéficiaire';
  }

  String get transferDisplayTitle {
    if (type != TxType.carnetTransfer && type != TxType.carnetReceived) {
      return type.label;
    }
    return transferIsIncoming
        ? 'Réception de $transferKindLabel'
        : 'Transfert de $transferKindLabel';
  }

  String transferDisplayTitleForViewer(String? viewerUserId) {
    if (type != TxType.carnetTransfer && type != TxType.carnetReceived) {
      return type.label;
    }
    return isIncomingTransferForViewer(viewerUserId)
        ? 'Réception de $transferKindLabel'
        : 'Transfert de $transferKindLabel';
  }

  String get displayTitle {
    if (type == TxType.carnetTransfer) {
      return transferDisplayTitle;
    }
    if (type == TxType.carnetReceived) {
      return transferDisplayTitle;
    }
    return type.label;
  }

  String displayTitleForViewer(String? viewerUserId) {
    final viewer = (viewerUserId ?? '').trim();
    if (viewer.isEmpty) {
      return displayTitle;
    }

    if (type == TxType.carnetTransfer || type == TxType.carnetReceived) {
      return transferDisplayTitleForViewer(viewer);
    }

    return displayTitle;
  }

  @override
  List<Object?> get props => [
    id,
    txReference,
    qrName,
    type,
    date,
    regularizationState,
    regularizationReference,
    regularizationDate,
    transferIsIncoming,
    transferUsesTickets,
    actorUserId,
    counterpartyUserId,
    actorUserName,
    counterpartyUserName,
  ];
}
