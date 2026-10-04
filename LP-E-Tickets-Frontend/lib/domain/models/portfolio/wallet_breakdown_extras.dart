/// Données complémentaires du portefeuille (hors solde principal affiché).
class WalletBreakdownExtras {
  const WalletBreakdownExtras({
    this.breakdownByFaceValue,
    this.breakdownByCarnetType,
    this.nearExpirationFaces = const [],
    this.expiredFaces = const [],
  });

  final Object? breakdownByFaceValue;
  final Object? breakdownByCarnetType;
  final List<dynamic> nearExpirationFaces;
  final List<dynamic> expiredFaces;

  WalletBreakdownExtras copyWith({
    Object? breakdownByFaceValue,
    Object? breakdownByCarnetType,
    List<dynamic>? nearExpirationFaces,
    List<dynamic>? expiredFaces,
  }) {
    return WalletBreakdownExtras(
      breakdownByFaceValue: breakdownByFaceValue ?? this.breakdownByFaceValue,
      breakdownByCarnetType:
          breakdownByCarnetType ?? this.breakdownByCarnetType,
      nearExpirationFaces: nearExpirationFaces ?? this.nearExpirationFaces,
      expiredFaces: expiredFaces ?? this.expiredFaces,
    );
  }

  bool get isEmpty =>
      breakdownByFaceValue == null &&
      breakdownByCarnetType == null &&
      nearExpirationFaces.isEmpty &&
      expiredFaces.isEmpty;
}
