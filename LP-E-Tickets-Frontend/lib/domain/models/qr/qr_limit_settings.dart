/// Persisted per-user limit used when issuing QRs.
class QrLimitSettings {
  const QrLimitSettings({required this.maxAmount, this.currency});

  final int? maxAmount;
  final String? currency;
}
