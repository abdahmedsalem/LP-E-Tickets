import 'package:intl/intl.dart';

import '../models/qr_token.dart';

/// Mappe les réponses JSON-RPC Odoo (QR mobile et consommation station) vers [QrToken].
class AcpecQrMapper {
  AcpecQrMapper._();

  static final DateTime _fallbackDate = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  static Map<String, dynamic> _unwrap(dynamic result) {
    if (result is! Map) {
      throw Exception('Réponse QR ACPEC invalide.');
    }
    var m = Map<String, dynamic>.from(result);
    if (m['ok'] == false) {
      throw Exception(m['message']?.toString() ?? 'Opération QR refusée.');
    }
    final err = m['error'];
    if (err is Map && m['ok'] != true) {
      throw Exception(err['message']?.toString() ?? 'Opération QR refusée.');
    }
    final data = m['data'];
    if (data is Map) {
      final dm = Map<String, dynamic>.from(data);
      if (dm['ok'] == false) {
        throw Exception(dm['message']?.toString() ?? 'Opération QR refusée.');
      }
      return dm;
    }
    return m;
  }

  static int _int(dynamic v, int d) {
    if (v == null) return d;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString().split('.').first) ?? d;
  }

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final parsed = DateTime.tryParse(s.replaceAll(' ', 'T'));
    if (parsed != null) return parsed;
    for (final pattern in [
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm:ss.SSS',
      'yyyy-MM-dd HH:mm:ss.SSSSSS',
      'yyyy-MM-ddTHH:mm:ss',
      'yyyy-MM-ddTHH:mm:ss.SSS',
      'yyyy-MM-ddTHH:mm:ss.SSSSSS',
      'dd/MM/yyyy HH:mm:ss',
      'dd/MM/yyyy HH:mm',
      'dd-MM-yyyy HH:mm:ss',
      'dd-MM-yyyy HH:mm',
      'yyyy-MM-dd',
      'dd/MM/yyyy',
      'dd-MM-yyyy',
    ]) {
      try {
        final parsed = DateFormat(pattern).parseStrict(s);
        if (pattern.contains('HH')) {
          return DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          );
        }
        return DateTime.utc(parsed.year, parsed.month, parsed.day);
      } catch (_) {}
    }
    final asInt = int.tryParse(s);
    if (asInt != null && asInt > 1000000000) {
      return asInt > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(asInt, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
    }
    return null;
  }

  static QrState _state(String? raw) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s.isEmpty) return QrState.active;

    if (s.contains('consom') ||
        (s.contains('consum') && !s.contains('inconsum'))) {
      return QrState.consumed;
    }
    if (s.contains('partial') || s.contains('partiel')) {
      return QrState.blocked;
    }
    if (s.contains('expir')) return QrState.expired;
    if (s.contains('bloqu') || s.contains('block')) return QrState.blocked;
    // 'split'/'splitted' n'existe pas côté backend — un QR retirÃ© ou séparé
    // devient active (enfant) ou blocked/expired (parent).

    switch (s) {
      case 'active':
      case 'draft':
      case 'valid':
        return QrState.active;
      case 'blocked':
      case 'block':
        return QrState.blocked;
      case 'consumed':
      case 'done':
      case 'used':
        return QrState.consumed;
      case 'expired':
        return QrState.expired;
      default:
        return QrState.active;
    }
  }

  static List<QrLine> _lines(
    dynamic v,
    String qrId, {
    required DateTime defaultExpiry,
  }) {
    if (v is! List) return [];
    final out = <QrLine>[];
    for (var i = 0; i < v.length; i++) {
      final e = v[i];
      if (e is! Map) continue;
      final row = Map<String, dynamic>.from(e);
      var fv = _int(
        row['face_value'] ?? row['nominal'] ?? row['unit_value'],
        0,
      );
      final qty = _int(row['qty'] ?? row['quantity'], 0);
      if (qty <= 0) continue;
      if (fv <= 0) {
        final amt = _int(
          row['amount'] ??
              row['line_amount'] ??
              row['subtotal'] ??
              row['total'],
          0,
        );
        if (amt > 0) {
          fv = (amt / qty).round();
        }
      }
      if (fv <= 0) continue;
      final exp =
          _date(
            row['expiration_date'] ??
                row['expiry_date'] ??
                row['expires_at'] ??
                row['expiresAt'] ??
                row['expires_on'] ??
                row['expiration'] ??
                row['expired_at'],
          ) ??
          defaultExpiry;
      final lineId =
          row['qr_line_id'] ?? row['id'] ?? row['line_id'] ?? row['qr_lineId'];
      out.add(
        QrLine(
          id: lineId?.toString() ?? 'ql-$i',
          qrId: qrId,
          lotId:
              row['lot_id']?.toString() ?? row['purchase_id']?.toString() ?? '',
          lotInternalRef:
              row['lot_ref']?.toString() ??
              row['purchase_ref']?.toString() ??
              '—',
          faceLineId:
              row['face_line_id']?.toString() ??
              row['acpec_line_id']?.toString() ??
              'fl-$i',
          carnetTypeId: row['carnet_type_id']?.toString() ?? '',
          carnetTypeCode:
              row['carnet_type_code']?.toString() ??
              row['carnet_type']?.toString() ??
              '',
          carnetTypeName:
              row['carnet_type_name']?.toString() ??
              row['carnet_name']?.toString() ??
              '',
          carnetSize: _int(
            row['face_count'] ??
                row['carnet_size'] ??
                row['faces_per_carnet'] ??
                0,
            0,
          ),
          faceValue: fv,
          qty: qty,
          expirationDate: exp,
        ),
      );
    }
    return out;
  }

  /// Construit les paramètres de détail QR : `public_code` pour un code scannable,
  /// ou `id` numérique si [qrId] est un entier pur.
  static Map<String, dynamic> detailParamsForRouteId(String qrId) {
    final t = Uri.decodeComponent(qrId.trim());
    if (t.isEmpty) return {'public_code': ''};
    final n = int.tryParse(t);
    if (n != null && '$n' == t) {
      return {'id': n};
    }
    return {'public_code': t};
  }

  static QrToken qrFromDataMap(
    Map<String, dynamic> row, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) {
    final publicCode =
        row['public_code']?.toString().trim() ??
        row['publicCode']?.toString().trim() ??
        row['code']?.toString().trim() ??
        '';
    if (publicCode.isEmpty) {
      throw Exception('Réponse QR sans public_code.');
    }
    final id = row['id']?.toString() ?? row['qr_id']?.toString() ?? publicCode;
    final state = _state(
      _pickQrStateRaw(row) ??
          row['state']?.toString() ??
          row['status']?.toString(),
    );
    final created =
        _date(
          row['date'] ??
              row['generated_at'] ??
              row['write_date'] ??
              row['created_at'] ??
              row['issued_at'] ??
              row['create_date'] ??
              row['created'] ??
              row['emitted_at'] ??
              row['issuedOn'],
        ) ??
        _fallbackDate;
    final expiresAt = _date(
      row['expires_at'] ?? row['expiresAt'] ?? row['expiration_at'],
    );
    var lines = _lines(
      row['lines'] ??
          row['lignes'] ??
          row['qr_lines'] ??
          row['composition'] ??
          row['technical_lines'],
      id,
      defaultExpiry: created.add(const Duration(days: 3650)),
    );
    if (lines.isEmpty) {
      final amt = _int(
        row['amount_total'] ?? row['total_amount'] ?? row['amount'] ?? 0,
        0,
      );
      final n = _int(
        row['face_qty_total'] ??
            row['total_qty'] ??
            row['qty_total'] ??
            row['qty'] ??
            0,
        0,
      );
      if (amt > 0 && n > 0) {
        final unit = (amt / n).round().clamp(1, 999999999);
        lines = [
          QrLine(
            id: 'syn',
            qrId: id,
            lotId: '',
            lotInternalRef: '—',
            faceLineId: '—',
            faceValue: unit,
            qty: n,
            expirationDate: created.add(const Duration(days: 3650)),
          ),
        ];
      } else if (amt > 0) {
        // Réponse minimaliste (ex. issue) : total seul — une ligne agrégée pour l’UI.
        lines = [
          QrLine(
            id: 'syn-total',
            qrId: id,
            lotId: '',
            lotInternalRef: '—',
            faceLineId: '—',
            faceValue: amt,
            qty: 1,
            expirationDate: created.add(const Duration(days: 3650)),
          ),
        ];
      }
    }
    return QrToken(
      id: id,
      publicCode: publicCode,
      internalRef: row['name']?.toString() ?? row['display_name']?.toString(),
      ownerId: ownerId,
      ownerName: ownerName,
      companyId: companyId,
      state: state,
      parentQrId:
          row['parent_id']?.toString() ?? row['parent_qr_id']?.toString(),
      lines: lines,
      createdAt: created,
      expiresAt: expiresAt,
      consumedAt: _date(row['consumed_at'] ?? row['used_at']),
      consumedByStationId: row['station_id']?.toString(),
      consumedByStationName: row['station_name']?.toString(),
      consumedByUserId: row['consumed_by_user_id']?.toString(),
    );
  }

  static QrToken fromRpcEnvelope(
    dynamic result, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) {
    final m = _unwrap(result);
    final merged = _mergeDetailPayload(m, includeTechnicalLines: true);
    return qrFromDataMap(
      merged,
      ownerId: ownerId,
      ownerName: ownerName,
      companyId: companyId,
    );
  }

  /// Réponse [`/mobile/qr/issue`] : ignore `technical_lines` (données internes).
  static QrToken fromRpcIssueEnvelope(
    dynamic result, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) {
    final m = _unwrap(result);
    final merged = _mergeDetailPayload(m, includeTechnicalLines: false);
    return qrFromDataMap(
      merged,
      ownerId: ownerId,
      ownerName: ownerName,
      companyId: companyId,
    );
  }

  /// Fusionne `data`, objet `qr` et listes sœurs (`lines`, `lignes`, …).
  static Map<String, dynamic> _mergeDetailPayload(
    Map<String, dynamic> root, {
    bool includeTechnicalLines = true,
  }) {
    Map<String, dynamic> envelope = root;
    final d = root['data'];
    if (d is Map) {
      envelope = Map<String, dynamic>.from(d);
    } else if (d is List && d.isNotEmpty && d.first is Map) {
      envelope = Map<String, dynamic>.from(d.first as Map);
    }

    Map<String, dynamic>? nested;
    for (final key in ['qr', 'token', 'record']) {
      final v = envelope[key];
      if (v is Map) {
        nested = Map<String, dynamic>.from(v);
        break;
      }
    }

    final merged = nested != null
        ? Map<String, dynamic>.from(nested)
        : Map<String, dynamic>.from(envelope);

    void adoptList(String target, List<String> keys) {
      if (includeTechnicalLines && target == 'lines') {
        for (final source in [envelope, root]) {
          final technical = source['technical_lines'];
          if (technical is List && technical.isNotEmpty) {
            merged[target] = technical;
            return;
          }
        }
      }
      if (merged[target] is List && (merged[target] as List).isNotEmpty) {
        return;
      }
      for (final source in [envelope, root]) {
        for (final k in keys) {
          if (source[k] is List) {
            merged[target] = source[k];
            return;
          }
        }
      }
    }

    adoptList('lines', [
      'lines',
      'lignes',
      'qr_lines',
      'composition',
      if (includeTechnicalLines) 'technical_lines',
    ]);

    for (final k in [
      'public_code',
      'state',
      'status',
      'date',
      'generated_at',
      'write_date',
      'created_at',
      'issued_at',
      'emitted_at',
      'create_date',
      'write_date',
      'consumed_at',
      'used_at',
      'station_name',
      'station_id',
      'parent_id',
      'parent_qr_id',
      'expires_at',
      'name',
      'display_name',
    ]) {
      if (merged[k] == null && envelope[k] != null) {
        merged[k] = envelope[k];
      }
    }

    return merged;
  }

  static List<QrToken> listFromRpc(
    dynamic result, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) {
    if (result is List) {
      return _mapQrList(
        result,
        ownerId: ownerId,
        ownerName: ownerName,
        companyId: companyId,
      );
    }
    final m = _unwrap(result);
    dynamic raw =
        m['lignes'] ??
        m['items'] ??
        m['qrs'] ??
        m['records'] ??
        m['rows'] ??
        m['results'];
    if (raw == null && m['data'] is List) raw = m['data'];
    if (raw is! List && m['data'] is Map) {
      final d = Map<String, dynamic>.from(m['data'] as Map);
      raw = d['lignes'] ?? d['items'] ?? d['qrs'] ?? d['records'] ?? d['rows'];
    }
    if (raw is! List) return [];
    return _mapQrList(
      raw,
      ownerId: ownerId,
      ownerName: ownerName,
      companyId: companyId,
    );
  }

  static List<QrToken> _mapQrList(
    List<dynamic> raw, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) {
    final out = <QrToken>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(
          qrFromDataMap(
            Map<String, dynamic>.from(e),
            ownerId: ownerId,
            ownerName: ownerName,
            companyId: companyId,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  static Map<String, dynamic> _mergeNestedMaps(Map<String, dynamic> root) {
    var merged = Map<String, dynamic>.from(root);
    for (final key in ['qr', 'transaction', 'record', 'result']) {
      final nested = root[key];
      if (nested is Map) {
        // L’objet imbriqué (souvent `qr`) prime sur l’enveloppe (`state: success`).
        merged = {...merged, ...Map<String, dynamic>.from(nested)};
      }
    }
    return merged;
  }

  static String? _pickQrStateRaw(Map<String, dynamic> m) {
    for (final k in ['qr_state', 'qrState', 'state', 'status']) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isEmpty || s == 'false') continue;
      final lower = s.toLowerCase();
      if (lower == 'success' ||
          lower == 'ok' ||
          lower == 'true' ||
          lower == '1') {
        continue;
      }
      return s;
    }
    return null;
  }

  /// Pour afficher le dialogue après `station/qr/use` (totaux optionnels).
  static QrToken fromStationUseResult(
    dynamic result, {
    required String scannedPublicCode,
    required String stationUserId,
    required String stationUserName,
    required String companyId,
  }) {
    final m = _mergeNestedMaps(_unwrap(result));

    String? transactionId;
    for (final k in [
      'transaction_id',
      'transactionId',
      'tx_id',
      'txId',
      'move_id',
      'id',
    ]) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s != 'false' && s != '0') {
        transactionId = s;
        break;
      }
    }

    final envelopeOk = m['ok'] == true;
    final qrStateRaw = _pickQrStateRaw(m) ?? 'consumed';
    var state = _state(qrStateRaw);

    if (envelopeOk && state != QrState.blocked && state != QrState.expired) {
      state = QrState.consumed;
    }

    if (transactionId == null && !envelopeOk && state != QrState.consumed) {
      throw Exception(
        'Consommation refusée : réponse serveur sans transaction ni état consommé.',
      );
    }

    final amount = _int(
      m['amount_total'] ?? m['amount'] ?? m['total_amount'] ?? m['total'],
      0,
    );
    var qty = _int(
      m['face_qty'] ?? m['qty_total'] ?? m['total_qty'] ?? m['qty'],
      0,
    );
    final lineRows = m['lines'] ?? m['transaction_lines'] ?? m['qr_lines'];
    final lines = lineRows is List && lineRows.isNotEmpty
        ? _lines(
            lineRows,
            transactionId ?? 'consumed',
            defaultExpiry: DateTime.now(),
          )
        : <QrLine>[];

    if (lines.isEmpty) {
      var fv = _int(m['face_value'] ?? m['nominal'], 0);
      if (qty <= 0) qty = 1;
      if (fv <= 0 && amount > 0) {
        fv = (amount / qty).round();
      }
      if (fv <= 0) fv = amount > 0 ? amount : 1;
      lines.add(
        QrLine(
          id: 'use-0',
          qrId: transactionId ?? 'consumed',
          lotId: m['lot_id']?.toString() ?? '',
          lotInternalRef:
              m['lot_ref']?.toString() ?? m['lot_name']?.toString() ?? '—',
          faceLineId: '—',
          faceValue: fv,
          qty: qty,
          expirationDate: DateTime.now(),
        ),
      );
    }

    final resolvedCode =
        m['public_code']?.toString().trim() ??
        m['publicCode']?.toString().trim() ??
        scannedPublicCode;

    return QrToken(
      id: transactionId ?? 'station-use',
      publicCode: resolvedCode.isNotEmpty ? resolvedCode : scannedPublicCode,
      ownerId: stationUserId,
      ownerName: stationUserName,
      companyId: companyId,
      state: state,
      lines: lines,
      createdAt: DateTime.now(),
      consumedAt: DateTime.now(),
      stationConsumeTransactionId: transactionId,
    );
  }

  /// Lève si la réponse split indique un échec (`ok: false`).
  static void assertSplitOk(dynamic raw) {
    if (raw == null) return;
    if (raw is! Map) return;
    final m = Map<String, dynamic>.from(raw);
    if (m['ok'] == false) {
      throw Exception(
        m['message']?.toString() ?? 'Impossible de partager ce QR.',
      );
    }
    final data = m['data'];
    if (data is Map) {
      final d = Map<String, dynamic>.from(data);
      if (d['ok'] == false) {
        throw Exception(
          d['message']?.toString() ?? 'Impossible de partager ce QR.',
        );
      }
    }
  }
}
