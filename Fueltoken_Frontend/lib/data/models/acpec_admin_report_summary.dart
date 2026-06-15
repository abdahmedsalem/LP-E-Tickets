import 'package:equatable/equatable.dart';

/// Compteurs du tableau de bord admin.
class AcpecAdminReportSummary extends Equatable {
  const AcpecAdminReportSummary({
    required this.purchasesSubmitted,
    required this.purchasesApproved,
    required this.consumptionVolumeMru,
    required this.wallets,
    required this.stationsActive,
    required this.qrActive,
    required this.qrBlocked,
    required this.qrConsumed,
    required this.qrExpired,
    required this.transactions,
  });

  final int purchasesSubmitted;
  final int purchasesApproved;

  /// Volume consommé (MRU) agrégé côté serveur.
  final int consumptionVolumeMru;
  final int wallets;
  final int stationsActive;
  final int qrActive;
  final int qrBlocked;
  final int qrConsumed;
  final int qrExpired;
  final int transactions;

  factory AcpecAdminReportSummary.fromRpc(dynamic raw) {
    if (raw is! Map) {
      throw Exception('Réponse résumé admin invalide.');
    }
    final top = Map<String, dynamic>.from(raw);
    if (top['ok'] == false) {
      throw Exception(
        top['message']?.toString() ?? 'Résumé admin indisponible.',
      );
    }

    Map<String, dynamic> m = top;
    final d = top['data'];
    if (d is Map) {
      final dm = Map<String, dynamic>.from(d);
      if (dm['ok'] == false) {
        throw Exception(
          dm['message']?.toString() ?? 'Résumé admin indisponible.',
        );
      }
      m = dm;
    }

    final counters = m['counters'];
    Map<String, dynamic> counterMap = m;
    if (counters is Map) {
      counterMap = Map<String, dynamic>.from(counters);
    } else if (m['summary'] is Map) {
      counterMap = Map<String, dynamic>.from(m['summary'] as Map);
    }

    return AcpecAdminReportSummary(
      purchasesSubmitted: _intAny(
        counterMap,
        const [
          'purchases_submitted',
          'purchasesSubmitted',
          'purchase_submitted',
          'purchases_pending',
          'pending_purchases',
        ],
        fallbackMaps: [m],
      ),
      purchasesApproved: _intAny(
        counterMap,
        const [
          'purchases_approved',
          'purchasesApproved',
          'purchase_approved',
          'purchases_validated',
        ],
        fallbackMaps: [m],
      ),
      consumptionVolumeMru: _intAny(
        counterMap,
        const [
          'consumption_volume_mru',
          'consumption_total_mru',
          'consumed_volume_mru',
          'volume_consumed_mru',
          'volume_consumed',
          'consumption_total',
          'consumed_amount',
          'total_consumed',
          'total_consumed_mru',
          'station_consumption_total',
          'transactions_amount_total',
          'consumption_amount',
        ],
        fallbackMaps: [m],
      ),
      wallets: _intAny(
        counterMap,
        const ['wallets', 'wallet_count', 'walletCount'],
        fallbackMaps: [m],
      ),
      stationsActive: _intAny(
        counterMap,
        const ['stations_active', 'stationsActive', 'active_stations'],
        fallbackMaps: [m],
      ),
      qrActive: _intAny(
        counterMap,
        const ['qr_active', 'qrActive'],
        fallbackMaps: [m],
      ),
      qrBlocked: _intAny(
        counterMap,
        const ['qr_blocked', 'qrBlocked'],
        fallbackMaps: [m],
      ),
      qrConsumed: _intAny(
        counterMap,
        const ['qr_consumed', 'qrConsumed'],
        fallbackMaps: [m],
      ),
      qrExpired: _intAny(
        counterMap,
        const ['qr_expired', 'qrExpired'],
        fallbackMaps: [m],
      ),
      transactions: _intAny(
        counterMap,
        const ['transactions', 'transaction_count', 'transactionCount'],
        fallbackMaps: [m],
      ),
    );
  }

  static int _intAny(
    Map<String, dynamic> m,
    List<String> keys, {
    List<Map<String, dynamic>> fallbackMaps = const [],
  }) {
    for (final map in [m, ...fallbackMaps]) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        if (v is int) return v;
        if (v is num) return v.round();
        final s = v.toString().trim();
        if (s.isEmpty || s == 'false') continue;
        final n = int.tryParse(s.split('.').first);
        if (n != null) return n;
      }
    }
    return 0;
  }

  @override
  List<Object?> get props => [
    purchasesSubmitted,
    purchasesApproved,
    consumptionVolumeMru,
    wallets,
    stationsActive,
    qrActive,
    qrBlocked,
    qrConsumed,
    qrExpired,
    transactions,
  ];
}
