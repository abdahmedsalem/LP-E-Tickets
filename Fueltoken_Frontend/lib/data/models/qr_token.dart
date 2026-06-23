import 'package:equatable/equatable.dart';

// États réels du backend : active, blocked, consumed, expired.
// `split` n'existe pas côté serveur — retirer_qr et separer_qr produisent
// des enfants actifs, le parent devient blocked ou expired selon les cas.
enum QrState { active, blocked, consumed, expired }

extension QrStateX on QrState {
  String get label {
    switch (this) {
      case QrState.active:
        return 'Actif';
      case QrState.blocked:
        return 'Bloqué';
      case QrState.consumed:
        return 'Consommé';
      case QrState.expired:
        return 'Expiré';
    }
  }

  /// Paramètre JSON `state` pour la liste des QR (ACPEC).
  String get apiListState {
    switch (this) {
      case QrState.active:
        return 'active';
      case QrState.blocked:
        return 'blocked';
      case QrState.consumed:
        return 'consumed';
      case QrState.expired:
        return 'expired';
    }
  }
}

/// acpec.fuel.qr.line — keeps the link to lot + face line for audit.
class QrLine extends Equatable {
  final String id;
  final String qrId;
  final String lotId;
  final String lotInternalRef;
  final String faceLineId;
  final String carnetTypeId;
  final String carnetTypeCode;
  final String carnetTypeName;
  final int carnetSize;
  final int faceValue;
  final int qty;
  final DateTime expirationDate;

  const QrLine({
    required this.id,
    required this.qrId,
    required this.lotId,
    required this.lotInternalRef,
    required this.faceLineId,
    this.carnetTypeId = '',
    this.carnetTypeCode = '',
    this.carnetTypeName = '',
    this.carnetSize = 0,
    required this.faceValue,
    required this.qty,
    required this.expirationDate,
  });

  int get amount => qty * faceValue;
  bool get isExpired => DateTime.now().isAfter(expirationDate);

  @override
  List<Object?> get props => [
    id,
    lotId,
    faceLineId,
    carnetTypeId,
    carnetTypeCode,
    carnetTypeName,
    carnetSize,
    faceValue,
    qty,
    expirationDate,
  ];
}

/// acpec.fuel.qr — public-scannable envelope of face lines.
class QrToken extends Equatable {
  final String id;
  final String publicCode; // not predictable, used by mobile/station
  final String? qrNumericCode; // user-facing 12-digit manual entry code
  final String? internalRef;
  final String ownerId;
  final String ownerName;
  final String companyId;
  final QrState state;
  final String? parentQrId;
  final List<QrLine> lines;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? consumedAt;
  final String? consumedByStationId;
  final String? consumedByStationName;
  final String? consumedByUserId;

  /// Identifiant de transaction renvoyé après une consommation station réussie.
  final String? stationConsumeTransactionId;

  const QrToken({
    required this.id,
    required this.publicCode,
    this.qrNumericCode,
    this.internalRef,
    required this.ownerId,
    required this.ownerName,
    required this.companyId,
    required this.state,
    this.parentQrId,
    required this.lines,
    required this.createdAt,
    this.expiresAt,
    this.consumedAt,
    this.consumedByStationId,
    this.consumedByStationName,
    this.consumedByUserId,
    this.stationConsumeTransactionId,
  });

  int get totalQty => lines.fold(0, (s, l) => s + l.qty);
  int get totalAmount => lines.fold(0, (s, l) => s + l.amount);
  DateTime get generatedAt => createdAt;

  /// Vrai si au moins une ligne a un lot exploitable à afficher (pas uniquement des tirets).
  bool get hasAuditableLotOrigins {
    for (final l in lines) {
      final r = l.lotInternalRef.trim();
      if (r.isNotEmpty && r != '—') return true;
    }
    return false;
  }

  bool get hasMixedExpiration {
    if (lines.isEmpty) return false;
    final hasValid = lines.any((l) => !l.isExpired);
    final hasExpired = lines.any((l) => l.isExpired);
    return hasValid && hasExpired;
  }

  /// User-facing aggregation: { faceValue → qty }
  Map<int, int> get aggregatedByFaceValue {
    final map = <int, int>{};
    for (final line in lines) {
      map[line.faceValue] = (map[line.faceValue] ?? 0) + line.qty;
    }
    return map;
  }

  QrToken copyWith({
    QrState? state,
    DateTime? expiresAt,
    DateTime? consumedAt,
    String? consumedByStationId,
    String? consumedByStationName,
    String? consumedByUserId,
    String? stationConsumeTransactionId,
  }) {
    return QrToken(
      id: id,
      publicCode: publicCode,
      qrNumericCode: qrNumericCode,
      internalRef: internalRef,
      ownerId: ownerId,
      ownerName: ownerName,
      companyId: companyId,
      state: state ?? this.state,
      parentQrId: parentQrId,
      lines: lines,
      createdAt: createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      consumedAt: consumedAt ?? this.consumedAt,
      consumedByStationId: consumedByStationId ?? this.consumedByStationId,
      consumedByStationName:
          consumedByStationName ?? this.consumedByStationName,
      consumedByUserId: consumedByUserId ?? this.consumedByUserId,
      stationConsumeTransactionId:
          stationConsumeTransactionId ?? this.stationConsumeTransactionId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    publicCode,
    qrNumericCode,
    state,
    lines,
    stationConsumeTransactionId,
    expiresAt,
  ];
}
