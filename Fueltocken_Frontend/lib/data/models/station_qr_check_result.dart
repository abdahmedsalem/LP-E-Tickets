import 'package:equatable/equatable.dart';

/// Résultat de la vérification d’un QR côté station.
class StationQrCheckResult extends Equatable {
  const StationQrCheckResult({
    required this.canConsume,
    this.reason,
    this.publicCode,
  });

  final bool canConsume;
  final String? reason;
  final String? publicCode;

  factory StationQrCheckResult.fromRpc(dynamic raw) {
    if (raw is! Map) {
      throw Exception('Réponse station/qr/check invalide.');
    }
    var m = Map<String, dynamic>.from(raw);
    if (m['ok'] == false) {
      throw Exception(
        m['message']?.toString() ?? 'Vérification QR refusée.',
      );
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
        m = {
          ...m,
          ...Map<String, dynamic>.from(nested),
        };
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
        reason ??= 'Ce QR a déjà été consommé et ne peut plus être scanné.';
      } else if (state.contains('expir')) {
        can = false;
        reason ??= 'Ce QR est expiré.';
      } else if (state.contains('block') || state.contains('bloqu')) {
        can = false;
        reason ??=
            'Ce QR est bloqué. Le client doit le partager (split) avant utilisation.';
      } else if (state == 'split' || state.contains('split')) {
        can = false;
        reason ??= 'Ce QR parent a été partagé ; scannez un QR enfant actif.';
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
              deny.toLowerCase().contains('déjà') ||
              deny.toLowerCase().contains('deja'))) {
        can = false;
        reason ??= deny;
      }
    }

    return StationQrCheckResult(
      canConsume: can,
      reason: (reason != null && reason.isNotEmpty) ? reason : null,
      publicCode: (pub != null && pub.isNotEmpty) ? pub : null,
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

  @override
  List<Object?> get props => [canConsume, reason, publicCode];
}
