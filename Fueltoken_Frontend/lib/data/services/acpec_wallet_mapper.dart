import '../../data/models/face_line.dart';
import '../../data/models/wallet_breakdown_extras.dart';
import 'odoo_jsonrpc_client.dart';

/// Normalise la réponse JSON-RPC ACPEC « wallet courant » vers l’état UI.
///
/// Tolère plusieurs formes (`data` imbriqué, `wallet` / `total_available_value` string/num, etc.).
class AcpecWalletMapper {
  AcpecWalletMapper._();

  static void _failIfEnvelopeAuth(Map<String, dynamic> m) {
    final bad = m['ok'] == false || m['ok'] == 0 || m['ok'] == 'false';
    if (!bad) return;
    final code = m['code']?.toString().toLowerCase() ?? '';
    final msg = m['message']?.toString().toLowerCase() ?? '';
    if (code.contains('auth_required') ||
        msg.contains('auth_required') ||
        code.contains('unauthorized') ||
        msg.contains('unauthorized') ||
        msg.contains('session expir') ||
        msg.contains('session expired') ||
        msg.contains('authenticate') ||
        msg.contains('non autoris') ||
        msg.contains('not authenticated')) {
      throw OdooJsonRpcException(
        m['message']?.toString() ?? 'AUTH_REQUIRED',
        code: 401,
      );
    }
  }

  static Map<String, dynamic> _unwrap(dynamic result) {
    if (result is! Map) return {};
    var m = Map<String, dynamic>.from(result);
    _failIfEnvelopeAuth(m);
    if (m['ok'] == false || m['ok'] == 0) {
      throw Exception(m['message']?.toString() ?? 'wallet ACPEC indisponible.');
    }
    final data = m['data'];
    if (data is Map) {
      m = Map<String, dynamic>.from(data);
      _failIfEnvelopeAuth(m);
    }
    if (m['ok'] == false || m['ok'] == 0) {
      throw Exception(m['message']?.toString() ?? 'wallet ACPEC indisponible.');
    }
    return m;
  }

  static int _parseAmount(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    final d = double.tryParse(s.replaceAll(',', '.'));
    if (d != null) return d.round();
    return int.tryParse(s.split('.').first) ?? 0;
  }

  /// Construit `byFaceValue` depuis `breakdown_by_face_value` (liste ou map).
  static Map<int, int> _byFaceFromBreakdown(dynamic raw) {
    final out = <int, int>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final fv = _parseAmount(e.key);
        final qty = _parseAmount(e.value);
        if (fv > 0 && qty != 0) {
          out[fv] = (out[fv] ?? 0) + qty;
        }
      }
      return out;
    }
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final row = Map<String, dynamic>.from(e);
        final fv = _parseAmount(
          row['face_value'] ?? row['denomination'] ?? row['value'],
        );
        final qty = _parseAmount(
          row['qty'] ??
              row['quantity'] ??
              row['count'] ??
              row['available_qty'] ??
              row['qty_available'],
        );
        if (fv > 0 && qty != 0) {
          out[fv] = (out[fv] ?? 0) + qty;
        }
      }
    }
    return out;
  }

  /// Lignes synthétiques pour l’aperçu tickets quand l’API ne renvoie pas `lines`.
  static List<FaceLine> _faceLinesFromBreakdown(dynamic raw, String ownerId) {
    final lines = <FaceLine>[];
    if (raw is! List) return lines;
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      if (e is! Map) continue;
      final row = Map<String, dynamic>.from(e);
      final fv = _parseAmount(
        row['face_value'] ?? row['denomination'] ?? row['value'],
      );
      final qty = _parseAmount(
        row['qty'] ??
            row['quantity'] ??
            row['count'] ??
            row['available_qty'] ??
            row['qty_available'],
      );
      if (fv <= 0 || qty <= 0) continue;
      final code =
          row['carnet_type_code']?.toString() ??
          row['code']?.toString() ??
          row['type']?.toString() ??
          '';
      lines.add(
        FaceLine(
          id: row['id']?.toString() ?? 'acpec-bfv-$i',
          lotId: row['lot_id']?.toString() ?? '',
          lotInternalRef: row['lot_ref']?.toString() ?? '—',
          purchaseLineId: row['line_id']?.toString() ?? 'acpec-pl-$i',
          carnetTypeId: row['carnet_type_id']?.toString() ?? code,
          carnetTypeCode: code,
          carnetTypeName: row['carnet_type_name']?.toString() ?? '',
          carnetFaceCount: _parseAmount(
            row['face_count'] ??
                row['carnet_face_count'] ??
                row['carnet_type_face_count'],
          ),
          faceValue: fv,
          initialQty: qty,
          availableQty: qty,
          qrActiveQty: _parseAmount(row['qty_qr_active'] ?? 0),
          qrBlockedQty: _parseAmount(row['qty_qr_blocked'] ?? 0),
          consumedQty: _parseAmount(row['qty_consumed'] ?? 0),
          expiredQty: _parseAmount(row['qty_expired'] ?? 0),
          expirationDate: DateTime.now().add(const Duration(days: 3650)),
          ownerId: ownerId,
        ),
      );
    }
    return lines;
  }

  /// Retourne `amount` (MRU), répartition par valeur de face, [FaceLine], et détails pour la feuille « œil ».
  static ({
    int amount,
    Map<int, int> byFaceValue,
    List<FaceLine> faceLines,
    WalletBreakdownExtras? extras,
  })
  fromRpcResult(dynamic result, {required String ownerId}) {
    final m = _unwrap(result);
    final rawTotal =
        m['wallet'] ??
        m['total_available_value'] ??
        m['total_available'] ??
        m['available_value'] ??
        m['balance'];
    var amount = _parseAmount(rawTotal);

    final linesRaw = m['lines'] ?? m['face_lines'] ?? m['aggregated_lines'];
    final List<Map<String, dynamic>> rows = [];
    if (linesRaw is List) {
      for (final e in linesRaw) {
        if (e is Map) rows.add(Map<String, dynamic>.from(e));
      }
    }

    final byFaceValue = <int, int>{};
    final faceLines = <FaceLine>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final fv = _parseAmount(row['face_value']);
      final qty = _parseAmount(
        row['qty_available'] ?? row['available_qty'] ?? row['qty'],
      );
      if (fv <= 0) continue;
      byFaceValue[fv] = (byFaceValue[fv] ?? 0) + qty;

      final ref =
          row['purchase_ref']?.toString() ?? row['lot_ref']?.toString() ?? '—';
      faceLines.add(
        FaceLine(
          id: row['id']?.toString() ?? 'acpec-fl-$i',
          lotId:
              row['purchase_id']?.toString() ?? row['lot_id']?.toString() ?? '',
          lotInternalRef: ref,
          purchaseLineId: row['line_id']?.toString() ?? 'acpec-pl-$i',
          carnetTypeId: row['carnet_type_id']?.toString() ?? '',
          carnetTypeCode:
              row['carnet_type_code']?.toString() ??
              row['code']?.toString() ??
              '',
          carnetTypeName: row['carnet_type_name']?.toString() ?? '',
          carnetFaceCount: _parseAmount(
            row['face_count'] ??
                row['carnet_face_count'] ??
                row['carnet_type_face_count'],
          ),
          faceValue: fv,
          initialQty: qty,
          availableQty: qty,
          qrActiveQty: _parseAmount(row['qty_qr_active'] ?? 0),
          qrBlockedQty: _parseAmount(row['qty_qr_blocked'] ?? 0),
          consumedQty: _parseAmount(row['qty_consumed'] ?? 0),
          expiredQty: _parseAmount(row['qty_expired'] ?? 0),
          expirationDate: DateTime.now().add(const Duration(days: 3650)),
          ownerId: ownerId,
        ),
      );
    }

    final bfvRaw = m['breakdown_by_face_value'];
    if (byFaceValue.isEmpty && bfvRaw != null) {
      byFaceValue.addAll(_byFaceFromBreakdown(bfvRaw));
    }
    if (amount == 0 && byFaceValue.isNotEmpty) {
      var sum = 0;
      for (final e in byFaceValue.entries) {
        sum += e.key * e.value;
      }
      amount = sum;
    }
    if (faceLines.isEmpty && bfvRaw is List && bfvRaw.isNotEmpty) {
      faceLines.addAll(_faceLinesFromBreakdown(bfvRaw, ownerId));
    }

    final extras = WalletBreakdownExtras.fromWalletPayload(m);
    return (
      amount: amount,
      byFaceValue: byFaceValue,
      faceLines: faceLines,
      extras: extras,
    );
  }
}
