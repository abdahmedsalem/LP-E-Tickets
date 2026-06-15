import 'dart:math' as math;

import '../../core/utils/formatters.dart';
import '../models/carnet_type.dart';

/// Parse la réponse JSON-RPC des routes types de carnets (mobile ou admin).
///
/// Retourne `null` si la forme est inconnue ou `ok: false` — l’appelant peut
/// retomber sur l’inférence faces/wallet.
class AcpecCarnetTypesMapper {
  AcpecCarnetTypesMapper._();

  static int _int(dynamic v, [int d = 0]) {
    if (v == null) return d;
    if (v is int) return v;
    if (v is num) return v.round();
    final s = v.toString().trim();
    if (s.isEmpty) return d;
    final x = double.tryParse(s.replaceAll(',', '.'));
    if (x != null) return x.round();
    return int.tryParse(s.split('.').first) ?? d;
  }

  static bool _isActiveRow(Map<String, dynamic> m) {
    if (m.containsKey('active')) {
      final a = m['active'];
      if (a == false || a == 0) return false;
      if (a is String && a.toLowerCase() == 'false') return false;
    }
    if (m.containsKey('is_active')) {
      final a = m['is_active'];
      if (a == false || a == 0) return false;
      if (a is String && a.toLowerCase() == 'false') return false;
    }
    return true;
  }

  static Map<String, dynamic>? _unwrapEnvelope(dynamic result) {
    if (result is! Map) return null;
    var m = Map<String, dynamic>.from(result);
    if (m['ok'] == false) return null;
    final data = m['data'];
    if (data is Map) {
      m = Map<String, dynamic>.from(data);
    }
    if (m['ok'] == false) return null;
    return m;
  }

  static List<Map<String, dynamic>> _mapsFromList(List<dynamic> list) {
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  /// Extrait une liste d’objets « type de carnet » depuis plusieurs formes courantes.
  static List<Map<String, dynamic>>? _extractRows(dynamic result) {
    if (result is List) {
      return _mapsFromList(result);
    }
    final m = _unwrapEnvelope(result);
    if (m == null) return null;

    for (final key in [
      'types',
      'carnet_types',
      'carnetTypes',
      'records',
      'items',
      'lines',
      'rows',
    ]) {
      final v = m[key];
      if (v is List) {
        return _mapsFromList(v);
      }
    }
    final d = m['data'];
    if (d is List) {
      return _mapsFromList(d);
    }
    if (m.containsKey('id') ||
        m.containsKey('carnet_type_id') ||
        m.containsKey('type_id')) {
      return [m];
    }
    return null;
  }

  static CarnetType? _rowToType(
    Map<String, dynamic> row,
    String companyId, {
    required bool includeInactiveRows,
  }) {
    final active = _isActiveRow(row);
    if (!includeInactiveRows && !active) return null;

    final rawId = row['carnet_type_id'] ?? row['type_id'] ?? row['id'];
    var idStr = rawId?.toString().trim() ?? '';
    if (idStr.isEmpty || idStr == '0') return null;

    final codeRaw =
        row['carnet_type_code'] ?? row['code'] ?? row['technical_code'];
    var code = codeRaw?.toString().trim() ?? '';
    if (code.isEmpty) code = 'T$idStr';

    final nameRaw =
        row['carnet_type_name'] ??
        row['name'] ??
        row['display_name'] ??
        row['label'];
    var name = nameRaw?.toString().trim() ?? '';

    final faceValue = _int(
      row['face_value'] ??
          row['nominal'] ??
          row['ticket_value'] ??
          row['unit_value'] ??
          row['denomination'],
    );
    if (faceValue <= 0) return null;

    final size = math.max(
      1,
      _int(
        row['carnet_size'] ??
            row['size'] ??
            row['face_count'] ??
            row['tickets_per_carnet'] ??
            row['ticket_count'] ??
            row['qty_per_carnet'],
        1,
      ),
    );

    final validityDays = math.max(
      1,
      _int(row['validity_days'] ?? row['validity_after_validation_days'], 365),
    );

    final cidRaw = row['company_id'] ?? row['company_code'] ?? row['company'];
    var cid = cidRaw?.toString().trim() ?? '';
    if (cid.isEmpty) cid = companyId;

    if (name.isEmpty) {
      name = Formatters.carnetTypeLabel(size, faceValue);
    } else {
      name = Formatters.normalizeCarnetTypeLabel(
        name,
        fallbackSize: size,
        fallbackFaceValue: faceValue,
      );
    }

    return CarnetType(
      id: idStr,
      code: code,
      name: name,
      size: size,
      faceValue: faceValue,
      companyId: cid,
      active: active,
      validityDays: validityDays,
    );
  }

  /// `null` = échec d’enveloppe ou forme non reconnue (pas de liste exploitable).
  ///
  /// [includeInactiveRows] : pour la liste admin, inclure les lignes `active: false`.
  static List<CarnetType>? tryListFromRpc(
    dynamic result, {
    required String companyId,
    bool includeInactiveRows = false,
  }) {
    try {
      final rows = _extractRows(result);
      if (rows == null) return null;
      final out = <CarnetType>[];
      for (final row in rows) {
        final t = _rowToType(
          row,
          companyId,
          includeInactiveRows: includeInactiveRows,
        );
        if (t != null) out.add(t);
      }
      return out;
    } catch (_) {
      return null;
    }
  }
}
