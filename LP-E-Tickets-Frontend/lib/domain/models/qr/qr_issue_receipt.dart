/// Minimal confirmation returned after QR generation.
class QrIssueReceipt {
  const QrIssueReceipt({this.transactionReference});

  final String? transactionReference;
}
