import 'package:equatable/equatable.dart';

/// Résultat de la vérification d’un QR côté station.
class StationQrCheckResult extends Equatable {
  const StationQrCheckResult({
    required this.canConsume,
    this.reason,
    this.publicCode,
    this.clientName,
    this.clientPhone,
    this.clientEmail,
    this.totalAmount,
  });

  final bool canConsume;
  final String? reason;
  final String? publicCode;
  final String? clientName;
  final String? clientPhone;
  final String? clientEmail;
  final double? totalAmount;

  factory StationQrCheckResult.fromRpc(dynamic raw) {
    if (raw is! Map) {
      throw Exception('Réponse station/qr/check invalide.');
    }
    var m = Map<String, dynamic>.from(raw);
    if (m['ok'] == false) {
      throw Exception(m['message']?.toString() ?? 'Vérification QR refusée.');
    }
    final d = m['data'];
    if (d is Map) {
      final dm = Map<String, dynamic>.from(d);
      if (dm['ok'] == false) {
        throw Exception(
          dm['message']?.toString() ?? 'Vérification QR refusée.',
        );
      }
      m = dm;
    }
    for (final key in ['qr', 'record', 'result']) {
      final nested = m[key];
      if (nested is Map) {
        m = {...m, ...Map<String, dynamic>.from(nested)};
      }
    }

    final explicitCan = _boolOrNull(m, const [
      'can_consume',
      'canConsume',
      'consumable',
      'allowed',
    ]);
    var can = explicitCan ?? false;
    var reason = _stringAny(m, const [
      'reason',
      'message',
      'blocking_reason',
      'block_reason',
      'error',
    ]);
    final pub = _stringAny(m, const ['public_code', 'publicCode', 'code']);
    final clientName = _stringAny(m, const [
      'client_name',
      'clientName',
      'customer_name',
      'customerName',
      'partner_name',
      'partnerName',
      'buyer_name',
      'buyerName',
      'name',
    ]);
    final clientPhone = _stringAny(m, const [
      'client_phone',
      'clientPhone',
      'customer_phone',
      'customerPhone',
      'phone',
      'mobile',
      'tel',
      'telephone',
    ]);
    final clientEmail = _stringAny(m, const [
      'client_email',
      'clientEmail',
      'customer_email',
      'customerEmail',
      'email',
      'login',
    ]);
    final totalAmount = _doubleAny(m, const [
      'amount_total',
      'total_amount',
      'totalAmount',
      'amount',
      'total',
    ]);

    final state = _stringAny(m, const [
      'qr_state',
      'qrState',
      'state',
      'status',
    ])?.toLowerCase();

    if (state != null &&
        state != 'success' &&
        state != 'ok' &&
        state != 'true') {
      if (state == 'active' ||
          state == 'draft' ||
          state == 'valid' ||
          state.contains('activ')) {
        if (explicitCan == null) can = true;
      } else if (state == 'consumed' ||
          state == 'used' ||
          state == 'done' ||
          state.contains('consum') ||
          state.contains('consom')) {
        can = false;
        reason = 'Consommé';
      } else if (state.contains('expir')) {
        can = false;
        reason = 'QR expiré';
      } else if (state.contains('block') || state.contains('bloqu')) {
        can = false;
        reason ??=
            'Ce QR est bloqué. Le client doit le séparer avant utilisation.';
      } else if (state == 'split' || state.contains('split')) {
        can = false;
        reason ??= 'Ce QR parent a été séparé ; scannez un QR enfant actif.';
      } else if (explicitCan == null) {
        can = false;
      }
    }

    if (can && explicitCan == true) {
      final deny = _stringAny(m, const [
        'blocking_reason',
        'block_reason',
        'error',
        'deny_reason',
      ]);
      if (deny != null &&
          (deny.toLowerCase().contains('consom') ||
              deny.toLowerCase().contains('consum') ||
              deny.toLowerCase().contains('déjà ') ||
              deny.toLowerCase().contains('deja'))) {
        can = false;
        reason ??= deny;
      }
    }

    return StationQrCheckResult(
      canConsume: can,
      reason: (reason != null && reason.isNotEmpty) ? reason : null,
      publicCode: (pub != null && pub.isNotEmpty) ? pub : null,
      clientName: (clientName != null && clientName.isNotEmpty)
          ? clientName
          : null,
      clientPhone: (clientPhone != null && clientPhone.isNotEmpty)
          ? clientPhone
          : null,
      clientEmail: (clientEmail != null && clientEmail.isNotEmpty)
          ? clientEmail
          : null,
      totalAmount: totalAmount,
    );
  }

  static bool? _boolOrNull(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().toLowerCase().trim();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return null;
  }

  static String? _stringAny(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static double? _doubleAny(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) continue;
      final parsed = double.tryParse(s.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    canConsume,
    reason,
    publicCode,
    clientName,
    clientPhone,
    clientEmail,
    totalAmount,
  ];
}
