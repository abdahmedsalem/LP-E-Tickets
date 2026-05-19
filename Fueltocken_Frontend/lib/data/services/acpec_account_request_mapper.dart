import '../models/account_request_item.dart';

/// Page listée : éléments + métadonnées pagination si le serveur les renvoie.
class AccountRequestsListResult {
  const AccountRequestsListResult({
    required this.items,
    this.totalCount,
    required this.requestedOffset,
    required this.limit,
  });

  final List<AccountRequestItem> items;
  final int? totalCount;
  /// Offset envoyé dans les `params` pour cette réponse.
  final int requestedOffset;
  final int limit;

  bool get hasMore {
    if (items.isEmpty) return false;
    if (totalCount != null) {
      return requestedOffset + items.length < totalCount!;
    }
    return items.length >= limit;
  }
}

/// Parse la réponse JSON-RPC des demandes de compte admin.
class AcpecAccountRequestMapper {
  AcpecAccountRequestMapper._();

  static int? _intFrom(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static int? _readTotal(Map<String, dynamic> m) {
    for (final k in [
      'total',
      'total_count',
      'count',
      'total_rows',
      'length',
    ]) {
      final n = _intFrom(m[k]);
      if (n != null) return n;
    }
    final p = m['pagination'];
    if (p is Map) {
      final pm = Map<String, dynamic>.from(p);
      final n = _intFrom(pm['total'] ?? pm['total_count'] ?? pm['count']);
      if (n != null) return n;
    }
    return null;
  }

  /// Extrait la liste brute + total éventuel depuis [result] (liste seule ou enveloppe).
  static ({List<Map<String, dynamic>> maps, int? total}) _extractMapsAndTotal(
    dynamic result,
  ) {
    if (result is List) {
      final maps = result
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return (maps: maps, total: null);
    }
    if (result is! Map) {
      return (maps: <Map<String, dynamic>>[], total: null);
    }

    final m = Map<String, dynamic>.from(result);
    if (m['ok'] == false) {
      throw Exception(m['message']?.toString() ?? 'Erreur API.');
    }
    if (m['success'] == false) {
      throw Exception(
        m['error']?.toString() ??
            m['message']?.toString() ??
            'Erreur API.',
      );
    }

    int? topTotal = _readTotal(m);

    dynamic list;
    final data = m['data'];
    if (data is List) {
      list = data;
    } else if (data is Map) {
      final dm = Map<String, dynamic>.from(data);
      if (dm['ok'] == false) {
        throw Exception(dm['message']?.toString() ?? 'Erreur API.');
      }
      if (dm['success'] == false) {
        throw Exception(
          dm['error']?.toString() ??
              dm['message']?.toString() ??
              'Erreur API.',
        );
      }
      topTotal ??= _readTotal(dm);
      list = dm['items'] ??
          dm['requests'] ??
          dm['rows'] ??
          dm['results'] ??
          dm['records'] ??
          dm['list'];
    } else {
      list = m['items'] ??
          m['requests'] ??
          m['records'] ??
          m['rows'] ??
          m['results'];
    }

    if (list is! List) {
      return (maps: <Map<String, dynamic>>[], total: topTotal);
    }
    final maps = list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return (maps: maps, total: topTotal);
  }

  /// [requestedOffset] et [limit] servent au calcul [hasMore] si le total est absent.
  static AccountRequestsListResult parseListEnvelope(
    dynamic result, {
    required int requestedOffset,
    required int limit,
  }) {
    final (:maps, :total) = _extractMapsAndTotal(result);
    final items = maps.map(AccountRequestItem.fromMap).toList();
    return AccountRequestsListResult(
      items: items,
      totalCount: total,
      requestedOffset: requestedOffset,
      limit: limit,
    );
  }
}
