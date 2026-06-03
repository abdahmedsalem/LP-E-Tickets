import 'dart:convert';

class _CacheEntry {
  _CacheEntry(this.value, this.storedAt);

  final dynamic value;
  final DateTime storedAt;
}

/// Déduplication des appels identiques et cache mémoire à TTL court pour les lectures.
class AcpecFueltokenRpcCoordinator {
  AcpecFueltokenRpcCoordinator({
    this.cacheTtl = const Duration(seconds: 30),
  });

  /// Partagée par défaut pour éviter des requêtes doublées entre écrans.
  static final AcpecFueltokenRpcCoordinator shared =
      AcpecFueltokenRpcCoordinator();

  final Duration cacheTtl;

  final Map<String, Future<dynamic>> _inFlight = {};
  final Map<String, _CacheEntry> _cache = {};

  static String _cacheKey(String route, Map<String, dynamic>? params) {
    final normalized = _canonicalJson(params ?? const {});
    return '$route|${jsonEncode(normalized)}';
  }

  static dynamic _canonicalJson(Object? o) {
    if (o is Map) {
      final m = Map<String, dynamic>.from(o);
      final keys = m.keys.toList()..sort();
      return {for (final k in keys) k: _canonicalJson(m[k])};
    }
    if (o is List) {
      return o.map(_canonicalJson).toList();
    }
    return o;
  }

  /// Lectures pouvant être servies depuis le cache (TTL court). Les mutations ne sont jamais mises en cache.
  static bool isRouteCacheable(String route) {
    final r = route.toLowerCase();
    if (r.contains('/login') || r.contains('/logout')) return false;
    if (r.contains('/qr/use') || r.contains('/qr/issue')) {
      return false;
    }
    if (r.contains('/purchases/create')) return false;
    if (r.contains('/approve') || r.contains('/reject')) return false;
    if (r.contains('/stations/create') ||
        r.contains('/stations/update') ||
        r.contains('/stations/disable')) {
      return false;
    }
    if (r.contains('/carnet-types/create') ||
        r.contains('/carnet-types/update') ||
        r.contains('/carnet-types/delete')) {
      return false;
    }
    if (r.contains('/station/qr/check')) return false;
    if (r.contains('/wallet/')) return true;
    if (r.contains('/transactions')) return true;
    if (r.contains('/mobile/purchases') &&
        !r.contains('/create') &&
        !r.contains('/detail')) {
      return true;
    }
    if (r.contains('/purchases/detail')) return true;
    if (r.contains('/faces')) return true;
    if (r.contains('carnet-types')) return true;
    if (r.contains('/qr/list')) return true;
    if (r.contains('/qr/detail')) return true;
    if (r.contains('/station/profile')) return true;
    if (r.contains('/admin/purchases/pending')) return true;
    if (r.contains('/admin/purchases/detail')) return true;
    if (r.contains('/admin/stations/list')) return true;
    if (r.contains('/admin/reports/summary')) return true;
    if (r.contains('/admin/account-requests') &&
        !r.contains('/approve') &&
        !r.contains('/reject')) {
      return true;
    }
    return false;
  }

  Future<dynamic> execute({
    required String route,
    required Map<String, dynamic>? params,
    required Future<dynamic> Function() request,
  }) async {
    final key = _cacheKey(route, params);

    final inflight = _inFlight[key];
    if (inflight != null) {
      return inflight;
    }

    if (isRouteCacheable(route)) {
      final hit = _cache[key];
      if (hit != null &&
          DateTime.now().difference(hit.storedAt) < cacheTtl) {
        return hit.value;
      }
    }

    final fut = request();
    _inFlight[key] = fut;
    try {
      final result = await fut;
      if (isRouteCacheable(route)) {
        _cache[key] = _CacheEntry(result, DateTime.now());
      }
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  void clearCache() => _cache.clear();

  /// Invalide une entrée cache (ex. tirer au frais le détail d’un achat).
  void invalidate(String route, [Map<String, dynamic>? params]) {
    final key = _cacheKey(route, params);
    _cache.remove(key);
  }
}
