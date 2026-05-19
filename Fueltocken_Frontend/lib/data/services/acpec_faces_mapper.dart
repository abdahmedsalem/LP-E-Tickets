import 'package:intl/intl.dart';

import '../models/face_line.dart';

/// Mappe la réponse JSON-RPC des faces disponibles vers [FaceLine].
///
/// Tolère enveloppes `ok` / `data`, listes à la racine, clés `lines`, `lignes`, `items`, etc.
class AcpecFacesMapper {
  AcpecFacesMapper._();

  static List<dynamic> _linesFromPayload(Map<String, dynamic> m) {
    for (final key in [
      'lignes',
      'lines',
      'items',
      'faces',
      'records',
      'face_lines',
      'available_lines',
    ]) {
      final v = m[key];
      if (v is List && v.isNotEmpty) return List<dynamic>.from(v);
    }
    for (final key in [
      'lignes',
      'lines',
      'items',
      'faces',
      'records',
      'face_lines',
      'available_lines',
    ]) {
      final v = m[key];
      if (v is List) return List<dynamic>.from(v);
    }
    return [];
  }

  static Map<String, dynamic> _unwrapToMap(dynamic result) {
    if (result is List) {
      return {'lines': result};
    }
    if (result is! Map) {
      throw Exception('Réponse faces ACPEC invalide.');
    }
    var m = Map<String, dynamic>.from(result);
    if (m['ok'] == false) {
      throw Exception(m['message']?.toString() ?? 'Faces indisponibles.');
    }
    final data = m['data'];
    if (data is List) {
      return {'lines': data};
    }
    if (data is Map) {
      m = Map<String, dynamic>.from(data);
      if (m['ok'] == false) {
        throw Exception(m['message']?.toString() ?? 'Faces indisponibles.');
      }
      return m;
    }
    return m;
  }

  static int _parseAmount(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    final d = double.tryParse(s.replaceAll(',', '.').replaceAll(' ', ''));
    if (d != null) return d.round();
    return int.tryParse(s.split('.').first) ?? 0;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    var parsed = DateTime.tryParse(s);
    if (parsed != null) return parsed;
    for (final pattern in [
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm:ss.SSS',
      'dd/MM/yyyy',
      'yyyy-MM-dd',
    ]) {
      try {
        parsed = DateFormat(pattern).parseStrict(s);
        return parsed;
      } catch (_) {}
    }
    final asInt = int.tryParse(s);
    if (asInt != null && asInt > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
    }
    return null;
  }

  /// Extrait les lignes de faces ; l’UI peut filtrer sur les quantités disponibles.
  static List<FaceLine> fromRpcResult(
    dynamic result, {
    required String ownerId,
  }) {
    final m = _unwrapToMap(result);
    final linesRaw = _linesFromPayload(m);
    final faceLines = <FaceLine>[];
    for (var i = 0; i < linesRaw.length; i++) {
      final e = linesRaw[i];
      if (e is! Map) continue;
      final row = Map<String, dynamic>.from(e);

      final fv = _parseAmount(
        row['face_value'] ??
            row['faceValue'] ??
            row['nominal'] ??
            row['amount_per_face'] ??
            row['unit_value'],
      );

      final avail = _parseAmount(
        row['qty_available'] ??
            row['available_qty'] ??
            row['qty_disponible'] ??
            row['available'] ??
            row['qty'] ??
            row['quantity'],
      );

      final initial = _parseAmount(
        row['initial_qty'] ??
            row['qty_initial'] ??
            row['product_qty'] ??
            row['qty_total'] ??
            row['total_qty'],
      );

      if (fv <= 0 || avail <= 0) continue;

      final qrA = _parseAmount(
        row['qty_qr_active'] ?? row['qr_active_qty'] ?? 0,
      );
      final qrB = _parseAmount(
        row['qty_qr_blocked'] ?? row['qr_blocked_qty'] ?? 0,
      );
      final cons = _parseAmount(row['qty_consumed'] ?? row['consumed_qty'] ?? 0);
      final expi = _parseAmount(row['qty_expired'] ?? row['expired_qty'] ?? 0);

      final effectiveInitial = initial > 0 ? initial : avail;
      final sumParts = avail + qrA + qrB + cons + expi;
      var initialQty = effectiveInitial < avail ? avail : effectiveInitial;
      if (initialQty < sumParts) initialQty = sumParts;

      final ref = row['purchase_ref']?.toString() ??
          row['lot_ref']?.toString() ??
          row['lot_name']?.toString() ??
          row['order_ref']?.toString() ??
          row['lot_internal_ref']?.toString() ??
          '';

      final exp = _parseDate(
            row['expiration_date'] ??
                row['expiry_date'] ??
                row['date_expiration'] ??
                row['valid_until'],
          ) ??
          DateTime.now().add(const Duration(days: 3650));

      faceLines.add(
        FaceLine(
          id: row['id']?.toString() ?? 'acpec-face-$i',
          lotId: row['purchase_id']?.toString() ??
              row['lot_id']?.toString() ??
              row['order_id']?.toString() ??
              '',
          lotInternalRef: ref,
          purchaseLineId: row['line_id']?.toString() ??
              row['purchase_line_id']?.toString() ??
              'acpec-pl-$i',
          carnetTypeId: row['carnet_type_id']?.toString() ?? '',
          carnetTypeCode: row['carnet_type_code']?.toString() ??
              row['code']?.toString() ??
              row['product_code']?.toString() ??
              '',
          faceValue: fv,
          initialQty: initialQty,
          availableQty: avail,
          qrActiveQty: qrA,
          qrBlockedQty: qrB,
          consumedQty: cons,
          expiredQty: expi,
          expirationDate: exp,
          ownerId: ownerId,
        ),
      );
    }
    return faceLines;
  }
}
