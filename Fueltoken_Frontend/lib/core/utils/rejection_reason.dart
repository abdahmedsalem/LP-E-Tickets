/// Motif de rejet renvoyé par Odoo (souvent `false` / `true` quand absent).
String? sanitizeRejectionReason(dynamic value) {
  if (value == null) return null;
  if (value is bool) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  final low = s.toLowerCase();
  if (low == 'false' || low == 'true' || low == 'null' || low == '0') {
    return null;
  }
  return s;
}

/// Lit les clés courantes d’un objet JSON-RPC.
String? rejectionReasonFromMap(
  Map<String, dynamic> map, {
  List<String> keys = const [
    'rejection_reason',
    'reject_reason',
    'reject_note',
    'rejection_message',
    'motif_rejet',
    'reason',
    'note',
  ],
}) {
  for (final k in keys) {
    final parsed = sanitizeRejectionReason(map[k]);
    if (parsed != null) return parsed;
  }
  return null;
}

bool mapStateLooksRejected(String state) {
  final n = state.toLowerCase().trim();
  return n.contains('reject') || n.contains('refus');
}
