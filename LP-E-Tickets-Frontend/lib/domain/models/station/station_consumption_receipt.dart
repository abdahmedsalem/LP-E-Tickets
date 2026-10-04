import '../qr/qr_token.dart';

/// Résumé métier renvoyé après une consommation réussie côté station.
class StationConsumptionReceipt {
  const StationConsumptionReceipt({
    required this.qr,
    required this.consumedAt,
    this.amount,
    this.transactionName,
    this.publicCode,
  });

  final QrToken qr;
  final DateTime consumedAt;
  final Object? amount;
  final String? transactionName;
  final String? publicCode;
}
