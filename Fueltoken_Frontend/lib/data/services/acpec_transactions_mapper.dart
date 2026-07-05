import 'package:intl/intl.dart';

import '../models/purchase_lot.dart';
import '../models/business_transaction.dart';
import '../models/qr_token.dart';

/// Page d’historique des transactions (portefeuille ou station).
class AcpecTransactionsPage {
  const AcpecTransactionsPage({
    required this.items,
    this.totalCount,
    required this.hasMore,
  });

  final List<BusinessTransaction> items;
  final int? totalCount;
  final bool hasMore;
}

/// Mappe la réponse JSON-RPC ACPEC vers [BusinessTransaction] et la pagination.
class AcpecTransactionsMapper {
  AcpecTransactionsMapper._();

  static final DateTime _fallbackDate = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  /// Filtre côté client (l’API 5.6 ne filtre pas par type).
  static bool matchesClientFilter(BusinessTransaction tx, TxType filter) {
    if (tx.type == filter) return true;
    switch (filter) {
      case TxType.purchaseValidated:
        return _looksLikePurchaseValidated(tx) ||
            _looksLikePurchaseSubmitted(tx) ||
            _looksLikePurchaseRejected(tx);
      case TxType.purchaseSubmitted:
        return _looksLikePurchaseSubmitted(tx) ||
            _looksLikePurchaseValidated(tx) ||
            _looksLikePurchaseRejected(tx);
      case TxType.purchaseRejected:
        return _looksLikePurchaseRejected(tx) ||
            _looksLikePurchaseSubmitted(tx) ||
            _looksLikePurchaseValidated(tx);
      case TxType.qrBlocked:
        return _looksLikeQrBlocked(tx);
      case TxType.qrEmission:
        return _looksLikeQrEmission(tx);
      case TxType.qrSeparer:
        return _looksLikeQrSplit(tx);
      case TxType.qrRetirer:
        return _looksLikeQrRetirer(tx);
      case TxType.carnetTransfer:
        return _looksLikeCarnetTransfer(tx);
      case TxType.carnetReceived:
        return tx.type == TxType.carnetReceived;
      case TxType.stationConsumption:
        return _looksLikeStationConsumption(tx);
      case TxType.expiration:
        return _looksLikeExpiration(tx);
      case TxType.walletLedger:
        return tx.type == TxType.walletLedger;
    }
  }

  static bool _hasQrRef(BusinessTransaction tx) =>
      (tx.qrId != null && tx.qrId!.isNotEmpty) ||
      (tx.qrPublicCode != null && tx.qrPublicCode!.isNotEmpty);

  static String _txBlob(BusinessTransaction tx) {
    final parts = <String>[
      tx.note ?? '',
      tx.lotInternalRef ?? '',
      tx.qrPublicCode ?? '',
      tx.stationName ?? '',
      tx.id,
    ];
    return parts.join(' ').toLowerCase();
  }

  static TxType? _purchaseStateType(Map<String, dynamic> row) {
    final hasPurchase =
        _has(row, 'purchase_id', 'lot_id') ||
        _has(row, 'purchase_name', 'lot_name');
    if (!hasPurchase) return null;

    final stateBlob = _blob(
      row['purchase_state'],
      row['state'],
      row['status'],
      row['purchase_status'],
    );
    if (stateBlob.isEmpty) return null;

    if (stateBlob.contains('reject') ||
        stateBlob.contains('rejet') ||
        stateBlob.contains('cancel') ||
        stateBlob.contains('annul')) {
      return TxType.purchaseRejected;
    }
    if (stateBlob.contains('submit') ||
        stateBlob.contains('soumis') ||
        stateBlob.contains('pending') ||
        stateBlob.contains('draft')) {
      return TxType.purchaseSubmitted;
    }
    if (stateBlob.contains('valid') ||
        stateBlob.contains('approv') ||
        stateBlob.contains('done') ||
        stateBlob.contains('sale')) {
      return TxType.purchaseValidated;
    }
    return null;
  }

  static bool _blobHasBlock(String blob) =>
      blob.contains('block') ||
      blob.contains('bloqu') ||
      blob.contains('blocage') ||
      blob.contains('blocag');

  static bool _looksLikeQrBlocked(BusinessTransaction tx) {
    if (tx.type == TxType.qrBlocked) return true;
    if (!_hasQrRef(tx)) return false;
    if (_blobHasBlock(_txBlob(tx))) return true;
    return false;
  }

  static bool _looksLikeQrEmission(BusinessTransaction tx) {
    if (tx.type == TxType.qrEmission) return true;
    if (!_hasQrRef(tx)) return false;
    if (_looksLikeQrBlocked(tx)) return false;
    final blob = _txBlob(tx);
    return blob.contains('émission') ||
        blob.contains('emission') ||
        blob.contains('issue') ||
        blob.contains('emit');
  }

  static bool _looksLikeQrSplit(BusinessTransaction tx) {
    if (tx.type == TxType.qrSeparer) return true;
    if (!_hasQrRef(tx)) return false;
    if (_looksLikeQrBlocked(tx)) return false;
    final blob = _txBlob(tx);
    return blob.contains('split') ||
        blob.contains('partage') ||
        blob.contains('separer') ||
        blob.contains('séparer') ||
        blob.contains('separer_qr');
  }

  static bool _looksLikeQrRetirer(BusinessTransaction tx) {
    if (tx.type == TxType.qrRetirer) return true;
    if (!_hasQrRef(tx)) return false;
    if (_looksLikeQrBlocked(tx)) return false;
    final blob = _txBlob(tx);
    return blob.contains('retirer') ||
        blob.contains('retrait') ||
        blob.contains('withdraw') ||
        blob.contains('remove');
  }

  static bool _looksLikeCarnetTransfer(BusinessTransaction tx) {
    if (tx.type == TxType.carnetTransfer) return true;
    if (tx.type == TxType.carnetReceived) return true;
    final blob = _txBlob(tx);
    return blob.contains('transfert') ||
        blob.contains('transfer') ||
        blob.contains('transfert_carnet') ||
        blob.contains('carnet_transfer');
  }

  static bool _looksLikeStationConsumption(BusinessTransaction tx) {
    if (tx.type == TxType.stationConsumption) return true;
    final blob = _txBlob(tx);
    if (blob.contains('consomm') ||
        blob.contains('consum') ||
        blob.contains('station_use') ||
        blob.contains('fuel_use')) {
      return true;
    }
    final hasStation =
        (tx.stationId != null && tx.stationId!.isNotEmpty) ||
        (tx.stationName != null && tx.stationName!.isNotEmpty);
    if (hasStation && _hasQrRef(tx)) return true;
    return hasStation && (blob.contains('scan') || blob.contains('station'));
  }

  static bool _looksLikeExpiration(BusinessTransaction tx) {
    if (tx.type == TxType.expiration) return true;
    return _txBlob(tx).contains('expir');
  }

  static bool _looksLikePurchaseValidated(BusinessTransaction tx) {
    if (tx.type == TxType.purchaseValidated) return true;
    if (tx.type == TxType.purchaseSubmitted ||
        tx.type == TxType.purchaseRejected) {
      return false;
    }
    final hasLot =
        (tx.lotId != null && tx.lotId!.isNotEmpty) ||
        (tx.lotInternalRef != null && tx.lotInternalRef!.isNotEmpty);
    final hasQr =
        (tx.qrId != null && tx.qrId!.isNotEmpty) ||
        (tx.qrPublicCode != null && tx.qrPublicCode!.isNotEmpty);
    final hasStation =
        (tx.stationId != null && tx.stationId!.isNotEmpty) ||
        (tx.stationName != null && tx.stationName!.isNotEmpty);
    return hasLot && !hasQr && !hasStation && _txBlob(tx).contains('valid');
  }

  static bool _looksLikePurchaseRejected(BusinessTransaction tx) {
    if (tx.type == TxType.purchaseRejected) return true;
    if (tx.type == TxType.purchaseSubmitted ||
        tx.type == TxType.purchaseValidated) {
      return false;
    }
    final blob = _txBlob(tx);
    final hasLot =
        (tx.lotId != null && tx.lotId!.isNotEmpty) ||
        (tx.lotInternalRef != null && tx.lotInternalRef!.isNotEmpty);
    final hasQr =
        (tx.qrId != null && tx.qrId!.isNotEmpty) ||
        (tx.qrPublicCode != null && tx.qrPublicCode!.isNotEmpty);
    final hasStation =
        (tx.stationId != null && tx.stationId!.isNotEmpty) ||
        (tx.stationName != null && tx.stationName!.isNotEmpty);
    return hasLot &&
        !hasQr &&
        !hasStation &&
        (blob.contains('reject') ||
            blob.contains('rejet') ||
            blob.contains('cancel') ||
            blob.contains('annul'));
  }

  static bool _looksLikePurchaseSubmitted(BusinessTransaction tx) {
    if (tx.type == TxType.purchaseSubmitted) return true;
    if (tx.type == TxType.purchaseRejected ||
        tx.type == TxType.purchaseValidated) {
      return false;
    }
    final blob = _txBlob(tx);
    final hasLot =
        (tx.lotId != null && tx.lotId!.isNotEmpty) ||
        (tx.lotInternalRef != null && tx.lotInternalRef!.isNotEmpty);
    final hasQr =
        (tx.qrId != null && tx.qrId!.isNotEmpty) ||
        (tx.qrPublicCode != null && tx.qrPublicCode!.isNotEmpty);
    final hasStation =
        (tx.stationId != null && tx.stationId!.isNotEmpty) ||
        (tx.stationName != null && tx.stationName!.isNotEmpty);
    return hasLot &&
        !hasQr &&
        !hasStation &&
        (blob.contains('submit') ||
            blob.contains('soumis') ||
            blob.contains('pending') ||
            blob.contains('draft'));
  }

  static List<BusinessTransaction> fromSubmittedPurchases(
    List<PurchaseLot> lots, {
    required String userId,
    required String userName,
  }) {
    final out = <BusinessTransaction>[];
    for (final lot in lots) {
      if (lot.state == PurchaseLotState.draft) continue;
      final submittedDate = lot.submittedAt ?? lot.createdAt;
      out.add(
        BusinessTransaction(
          id: 'purchase-submitted-${lot.id}',
          type: TxType.purchaseSubmitted,
          date: submittedDate,
          userId: lot.clientId.isNotEmpty ? lot.clientId : userId,
          userName: lot.clientName.isNotEmpty ? lot.clientName : userName,
          lines: [
            for (final l in lot.lines)
              TransactionLine(
                id: l.id,
                carnetTypeId: l.carnetTypeId,
                carnetTypeCode: l.carnetTypeCode,
                carnetTypeName: l.carnetTypeName,
                faceValue: l.faceValue,
                qty: l.carnetCount,
                amount: l.lineAmount,
                carnetSize: l.carnetSize,
                expirationDate: lot.expirationDate,
                lotId: lot.id,
              ),
          ],
          lotId: lot.id,
          lotInternalRef: lot.internalRef,
          note: lot.state == PurchaseLotState.approved
              ? 'Validé après soumission'
              : lot.state == PurchaseLotState.rejected
              ? 'Rejeté après soumission'
              : lot.state.label,
        ),
      );
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// Repli si l’historique ne contient pas de mouvement « bloqué » explicite.
  static List<BusinessTransaction> fromBlockedQrTokens(
    List<QrToken> qrs, {
    required String userId,
    required String userName,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    final out = <BusinessTransaction>[];
    for (final qr in qrs) {
      if (qr.state != QrState.blocked || qr.lines.isEmpty) continue;
      if (dateFrom != null && qr.createdAt.isBefore(dateFrom)) continue;
      if (dateTo != null && qr.createdAt.isAfter(dateTo)) continue;

      final txLines = qr.lines
          .map(
            (l) => TransactionLine(
              id: l.id,
              carnetTypeId: '',
              carnetTypeCode: '',
              carnetTypeName: '',
              faceValue: l.faceValue,
              qty: l.qty,
              amount: l.amount,
              carnetSize: l.carnetSize,
              expirationDate: l.expirationDate,
              lotId: l.lotId,
              faceLineId: l.faceLineId,
              qrId: qr.id,
            ),
          )
          .toList();
      final first = qr.lines.first;

      out.add(
        BusinessTransaction(
          id: 'qr-block-${qr.id}',
          type: TxType.qrBlocked,
          date: qr.createdAt,
          userId: qr.ownerId.isNotEmpty ? qr.ownerId : userId,
          userName: qr.ownerName.isNotEmpty ? qr.ownerName : userName,
          lines: txLines,
          lotId: first.lotId,
          lotInternalRef: first.lotInternalRef,
          qrId: qr.id,
          qrPublicCode: qr.publicCode,
        ),
      );
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  static AcpecTransactionsPage parsePage(
    dynamic raw, {
    required String userId,
    required String userName,
    int requestedLimit = 20,
    int requestedOffset = 0,
  }) {
    if (raw is! Map) {
      throw Exception('Réponse historique transactions invalide.');
    }
    var m = Map<String, dynamic>.from(raw);
    if (m['ok'] == false) {
      throw Exception(
        m['message']?.toString() ?? 'Historique des transactions indisponible.',
      );
    }

    Map<String, dynamic> data = m;
    final d = m['data'];
    if (d is Map) {
      data = Map<String, dynamic>.from(d);
      if (data['ok'] == false) {
        throw Exception(
          data['message']?.toString() ??
              'Historique des transactions indisponible.',
        );
      }
    }

    final itemsRaw = _itemsList(data);
    if (itemsRaw.isEmpty && data['items'] == null && m['items'] is List) {
      itemsRaw.addAll(m['items'] as List);
    }

    final items = <BusinessTransaction>[];
    for (final e in itemsRaw) {
      if (e is! Map) continue;
      final tx = _mapTransaction(
        Map<String, dynamic>.from(e),
        userId: userId,
        userName: userName,
      );
      if (tx != null) items.add(tx);
    }

    final totalCount = _firstInt(data, const [
      'total',
      'total_count',
      'count',
      'total_records',
      'total_rows',
    ]);

    bool hasMore;
    final hm = data['has_more'] ?? data['hasMore'] ?? m['has_more'];
    if (hm is bool) {
      hasMore = hm;
    } else if (totalCount != null) {
      hasMore = requestedOffset + items.length < totalCount;
    } else {
      hasMore = items.length >= requestedLimit && items.isNotEmpty;
    }

    return AcpecTransactionsPage(
      items: items,
      totalCount: totalCount,
      hasMore: hasMore,
    );
  }

  /// Réponse route `…/transactions/detail` (`transaction_id`).
  static BusinessTransaction parseDetail(
    dynamic raw, {
    required String userId,
    required String userName,
  }) {
    if (raw is! Map) {
      throw Exception('Réponse détail transaction invalide.');
    }
    var root = Map<String, dynamic>.from(raw);
    _ensureOk(root);
    Map<String, dynamic> data = root;
    final d = root['data'];
    if (d is Map) {
      data = Map<String, dynamic>.from(d);
      _ensureOk(data);
    }

    Map<String, dynamic> row = data;
    for (final k in ['transaction', 'record', 'move', 'item', 'result']) {
      final v = data[k];
      if (v is Map) {
        row = Map<String, dynamic>.from(v);
        break;
      }
    }

    if (row['id'] == null &&
        row['transaction_id'] == null &&
        data['transaction_id'] != null) {
      row = Map<String, dynamic>.from(row);
      row['id'] = data['transaction_id'];
    }

    if (row['lines'] == null) {
      for (final lk in ['lines', 'transaction_lines', 'detail_lines']) {
        if (data[lk] is List) {
          row = Map<String, dynamic>.from(row);
          row['lines'] = data[lk];
          break;
        }
      }
    }

    final tx = _mapTransaction(row, userId: userId, userName: userName);
    if (tx == null) {
      throw Exception('Transaction introuvable.');
    }
    return tx;
  }

  static void _ensureOk(Map<String, dynamic> m) {
    if (m['ok'] == false) {
      throw Exception(
        m['message']?.toString() ?? 'Détail transaction indisponible.',
      );
    }
  }

  static List<dynamic> _itemsList(Map<String, dynamic> data) {
    for (final key in [
      'items',
      'transactions',
      'records',
      'history',
      'lines',
      'movements',
      'results',
    ]) {
      final v = data[key];
      if (v is List) return List<dynamic>.from(v);
    }
    return [];
  }

  static int? _firstInt(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) return v;
      if (v is num) return v.round();
      final i = int.tryParse(v.toString().trim());
      if (i != null) return i;
    }
    return null;
  }

  static BusinessTransaction? _mapTransaction(
    Map<String, dynamic> row, {
    required String userId,
    required String userName,
  }) {
    final idRaw = row['id'] ?? row['transaction_id'] ?? row['move_id'];
    if (idRaw == null) return null;
    final id = idRaw.toString();
    if (id.isEmpty) return null;

    var type = _resolveTxType(row);

    // Affiner la direction du transfert depuis le champ backend
    if (type == TxType.carnetTransfer) {
      final direction = row['transfer_direction']?.toString() ?? '';
      if (direction == 'incoming') {
        type = TxType.carnetReceived;
      } else if (direction.isEmpty) {
        // Fallback : lire la note si le backend ne renvoie pas encore le champ
        final note = row['note']?.toString().toLowerCase() ?? '';
        if (note.contains('entrant') ||
            note.contains('reçu de') ||
            note.contains('recu de')) {
          type = TxType.carnetReceived;
        }
      }
    }

    final date =
        _parseDate(
          row['date'] ??
              row['state_date'] ??
              row['create_date'] ??
              row['datetime'] ??
              row['written_date'] ??
              row['timestamp'] ??
              row['created_at'] ??
              row['date_order'] ??
              row['move_date'],
        ) ??
        _fallbackDate;
    final rowExpirationDate = _parseDate(
      row['expiration_date'] ??
          row['expiry_date'] ??
          row['expires_at'] ??
          row['expiresAt'] ??
          row['expiration'] ??
          row['expiration_at'],
    );

    final uid =
        row['user_id']?.toString() ?? row['partner_id']?.toString() ?? userId;
    final uname =
        row['user_name']?.toString() ??
        row['partner_name']?.toString() ??
        userName;

    final lines = _finalizeLines(
      row,
      _mapLines(row, fallbackExpiration: rowExpirationDate) ??
          _syntheticLine(
            row,
            transactionId: id,
            fallbackExpiration: rowExpirationDate,
          ),
    );

    if (lines.isEmpty) return null;

    // Extraire l'autre partie pour les transferts de carnets
    String? transferParty;
    String? transferPartyPhone;
    if (type == TxType.carnetTransfer || type == TxType.carnetReceived) {
      final fromField = row['transfer_other_party']?.toString().trim() ?? '';
      if (fromField.isNotEmpty && fromField != 'false') {
        transferParty = fromField;
      } else {
        // Fallback : extraire de la note "Transfert sortant vers X." / "Transfert entrant de X."
        final note = row['note']?.toString() ?? '';
        final outMatch = RegExp(
          r'vers\s+(.+?)\.?\s*$',
          caseSensitive: false,
        ).firstMatch(note);
        final inMatch = RegExp(
          r'de\s+(.+?)\.?\s*$',
          caseSensitive: false,
        ).firstMatch(note);
        if (type == TxType.carnetTransfer && outMatch != null) {
          transferParty = outMatch.group(1)?.trim();
        } else if (type == TxType.carnetReceived && inMatch != null) {
          transferParty = inMatch.group(1)?.trim();
        }
      }

      final phoneField =
          row['transfer_other_party_phone']?.toString().trim() ??
          row['transfer_other_party_mobile']?.toString().trim() ??
          row['transfer_phone']?.toString().trim() ??
          row['partner_phone']?.toString().trim() ??
          '';
      if (phoneField.isNotEmpty && phoneField != 'false') {
        transferPartyPhone = phoneField;
      }
    }

    return BusinessTransaction(
      id: id,
      txReference: _txReference(row, id),
      type: type,
      date: date,
      userId: uid,
      userName: uname,
      lines: lines,
      lotId: _stringField(row, 'lot_id', 'purchase_id'),
      lotInternalRef:
          _stringField(
            row,
            'lot_name',
            'purchase_name',
            'lot_internal_ref',
            'lot_ref',
            'purchase_ref',
          ) ??
          _lotRefFromName(row['name']),
      qrId: _stringField(row, 'qr_id'),
      qrPublicCode: _stringField(
        row,
        'qr_public_code',
        'public_code',
        'qr_code',
      ),
      stationId: _stringField(row, 'station_id'),
      stationName: _stringField(row, 'station_name'),
      note: _noteForRow(row),
      transferParty: transferParty,
      transferPartyPhone: transferPartyPhone,
    );
  }

  static String? _txReference(Map<String, dynamic> row, String fallbackId) {
    for (final key in [
      'name',
      'transaction_name',
      'tx_name',
      'transaction_ref',
      'reference',
    ]) {
      final v = row[key];
      if (v == null || v is bool) continue;
      final s = v.toString().trim();
      if (s.isEmpty || s == 'false' || s == 'true') continue;
      if (RegExp(r'^TX[-/\s]', caseSensitive: false).hasMatch(s)) {
        return s;
      }
    }
    return null;
  }

  static String? _lotRefFromName(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty || s == 'false' || s == 'true') return null;
    if (RegExp(r'^ACH[/\s-]', caseSensitive: false).hasMatch(s)) {
      return s;
    }
    return null;
  }

  static String? _stringField(
    Map<String, dynamic> row,
    String k1, [
    String? k2,
    String? k3,
    String? k4,
    String? k5,
  ]) {
    for (final k in [k1, k2, k3, k4, k5]) {
      if (k == null) continue;
      final v = row[k];
      if (v == null) continue;
      if (v is bool) continue;
      final s = v.toString().trim();
      if (s.isEmpty || s == '0' || s == 'false' || s == 'true') continue;
      return s;
    }
    return null;
  }

  /// QR passé en état bloqué (prioritaire sur `qr_issue`, `split`, etc.).
  static bool _rowIndicatesQrBlocked(Map<String, dynamic> row) {
    if (row['is_blocked'] == true ||
        row['blocked'] == true ||
        row['qr_blocked'] == true) {
      return true;
    }

    final state = _blob(
      row['state'],
      row['qr_state'],
      row['status'],
      row['move_state'],
      row['qr_status'],
    );
    if (_blobHasBlock(state)) return true;

    final typeBlob = _blobMany([
      row['type'],
      row['transaction_type'],
      row['kind'],
      row['move_type'],
      row['operation'],
      row['tx_type'],
      row['event_type'],
      row['operation_type'],
    ]);
    if (_blobHasBlock(typeBlob) || typeBlob.contains('qr_blocked')) {
      return true;
    }

    final ref = _blobMany([
      row['name'],
      row['reference'],
      row['display_name'],
      row['label'],
      row['description'],
    ]);
    if (ref.contains('ftx') && _blobHasBlock(ref)) return true;
    if (ref.contains('qr') && _blobHasBlock(ref)) return true;

    return false;
  }

  /// Libellé affiché : uniquement les types des filtres (pas « Opération » générique).
  static TxType _resolveTxType(Map<String, dynamic> row) {
    if (_rowIndicatesQrBlocked(row)) {
      return TxType.qrBlocked;
    }

    final purchaseStateType = _purchaseStateType(row);
    if (purchaseStateType != null) {
      return purchaseStateType;
    }

    final typeRaw =
        row['type'] ??
        row['transaction_type'] ??
        row['kind'] ??
        row['move_type'] ??
        row['operation'] ??
        row['tx_type'];

    final explicit = _parseTxType(typeRaw);
    if (explicit != TxType.walletLedger) return explicit;

    if (_isPurchaseValidatedRow(row, typeRaw?.toString() ?? '')) {
      return TxType.purchaseValidated;
    }
    if (_isPurchaseRejectedRow(row, typeRaw?.toString() ?? '')) {
      return TxType.purchaseRejected;
    }
    if (_isPurchaseSubmittedRow(row, typeRaw?.toString() ?? '')) {
      return TxType.purchaseSubmitted;
    }

    final state = _blob(
      row['state'],
      row['qr_state'],
      row['status'],
      row['move_state'],
    );
    final name = _blob(
      row['name'],
      row['description'],
      row['label'],
      row['reference'],
      row['display_name'],
    );
    final combined = '$state $name';

    if (_has(row, 'station_id', 'station_name') ||
        combined.contains('consomm') ||
        combined.contains('consum') ||
        combined.contains('station_use') ||
        combined.contains('fuel_use') ||
        (combined.contains('station') &&
            (combined.contains('scan') || combined.contains('use')))) {
      return TxType.stationConsumption;
    }

    if (combined.contains('expir') || combined.contains('expire')) {
      return TxType.expiration;
    }

    if (_blobHasBlock(combined)) {
      return TxType.qrBlocked;
    }

    if (combined.contains('separer') ||
        combined.contains('séparer') ||
        combined.contains('separer_qr')) {
      return TxType.qrSeparer;
    }

    if (combined.contains('retirer') ||
        combined.contains('retrait') ||
        combined.contains('withdraw') ||
        combined.contains('remove')) {
      return TxType.qrRetirer;
    }

    if (combined.contains('transfert') || combined.contains('transfer')) {
      // La direction est résolue après via transfer_direction
      return TxType.carnetTransfer;
    }

    if ((_has(row, 'purchase_id', 'lot_id') ||
            _has(row, 'purchase_name', 'lot_name')) &&
        (combined.contains('valid') ||
            combined.contains('approv') ||
            combined.contains('achat') ||
            combined.contains('purchase') ||
            combined.contains('lot'))) {
      return TxType.purchaseValidated;
    }

    if (_hasAny(row, 'qr_id', 'qr_public_code', 'public_code') ||
        RegExp(r'\bqr[\s_-]', caseSensitive: false).hasMatch(name)) {
      if (combined.contains('issue') ||
          combined.contains('emit') ||
          combined.contains('émission') ||
          combined.contains('emission')) {
        return TxType.qrEmission;
      }
      if (combined.contains('consomm') ||
          combined.contains('consum') ||
          combined.contains('use')) {
        return TxType.stationConsumption;
      }
      return TxType.qrEmission;
    }

    if ((_has(row, 'purchase_id', 'lot_id') ||
            _has(row, 'purchase_name', 'lot_name')) &&
        (combined.contains('reject') ||
            combined.contains('rejet') ||
            combined.contains('cancel') ||
            combined.contains('annul'))) {
      return TxType.purchaseRejected;
    }

    return TxType.walletLedger;
  }

  static bool _has(Map<String, dynamic> row, String k1, [String? k2]) {
    if (_rowHasKey(row, k1)) return true;
    if (k2 != null && _rowHasKey(row, k2)) return true;
    return false;
  }

  static bool _hasAny(
    Map<String, dynamic> row,
    String k1,
    String k2, [
    String? k3,
    String? k4,
  ]) {
    for (final k in [k1, k2, k3, k4]) {
      if (k != null && _rowHasKey(row, k)) return true;
    }
    return false;
  }

  static bool _rowHasKey(Map<String, dynamic> row, String k) {
    final v = row[k];
    if (v == null) return false;
    final s = v.toString().trim();
    return s.isNotEmpty && s != '0' && s != 'false';
  }

  static String _blob(dynamic a, [dynamic b, dynamic c, dynamic d, dynamic e]) {
    return _blobMany([a, b, c, d, e]);
  }

  static String _blobMany(List<dynamic> values) {
    final parts = <String>[];
    for (final v in values) {
      if (v == null) continue;
      final s = v.toString().trim().toLowerCase();
      if (s.isNotEmpty) parts.add(s);
    }
    return parts.join(' ');
  }

  static String? _noteForRow(Map<String, dynamic> row) {
    final qr =
        row['qr_public_code']?.toString() ?? row['public_code']?.toString();
    for (final key in ['description', 'label', 'reference']) {
      final raw = row[key]?.toString().trim();
      if (raw == null || raw.isEmpty) continue;
      var s = raw;
      if (qr != null && qr.isNotEmpty && s.contains(qr)) {
        s = s.replaceAll(qr, '').trim();
      }
      s = s.replaceAll(
        RegExp(r'[·•]\s*(true|false)\s*$', caseSensitive: false),
        '',
      );
      s = s.replaceAll(RegExp(r'\b(true|false)\b', caseSensitive: false), '');
      s = s
          .replaceAll(RegExp(r'[·•]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (s.isNotEmpty &&
          !RegExp(r'^[·•\s]+$').hasMatch(s) &&
          !RegExp(r'^qr[\s_-]', caseSensitive: false).hasMatch(s)) {
        return s;
      }
    }
    final name = _stringField(row, 'name', 'reference', 'display_name');
    if (name != null &&
        !RegExp(r'^qr[\s_-]', caseSensitive: false).hasMatch(name) &&
        (qr == null || !name.contains(qr))) {
      return name;
    }
    return null;
  }

  static TxType _parseTxType(dynamic v) {
    final s = v?.toString().toLowerCase().trim() ?? '';
    if (s.isEmpty) return TxType.walletLedger;

    // Plus spécifique d’abord (sous-chaînes ambiguës « qr »).
    if (s.contains('expir') ||
        s.contains('expired') ||
        s == 'expire' ||
        s.contains('expiration')) {
      return TxType.expiration;
    }
    if ((s.contains('split') || s.contains('partage')) &&
        (s.contains('qr') || s.contains('code'))) {
      return TxType.qrSeparer;
    }
    if (s.contains('separer') || s.contains('séparer') || s == 'separer_qr') {
      return TxType.qrSeparer;
    }
    if (s.contains('retirer') ||
        s.contains('retrait') ||
        s.contains('withdraw') ||
        s.contains('remove')) {
      return TxType.qrRetirer;
    }
    if (s.contains('transfert') ||
        s.contains('transfer') ||
        s.contains('transfert_carnet') ||
        s.contains('carnet_transfer')) {
      return TxType.carnetTransfer;
    }

    if (_blobHasBlock(s) || s == 'qr_blocked' || s == 'blocage_qr') {
      return TxType.qrBlocked;
    }

    if (s.contains('consomm') ||
        s.contains('consum') ||
        (s.contains('station') &&
            (s.contains('fuel') || s.contains('use') || s.contains('scan')))) {
      return TxType.stationConsumption;
    }
    if ((s == 'fuel' || s.contains('station_use')) &&
        !s.contains('validation')) {
      return TxType.stationConsumption;
    }

    if (s == 'purchase' ||
        s == 'achat' ||
        s == 'lot' ||
        s == 'purchase_approval' ||
        s == 'purchase_approve' ||
        s == 'lot_approval' ||
        s == 'lot_approve' ||
        (s.contains('purchase') &&
            !s.contains('qr') &&
            !s.contains('pending') &&
            !s.contains('reject'))) {
      return TxType.purchaseValidated;
    }
    if (s.contains('purchase') &&
        (s.contains('reject') || s.contains('rejet') || s.contains('cancel'))) {
      return TxType.purchaseRejected;
    }
    if (s.contains('purchase') &&
        (s.contains('submit') ||
            s.contains('soumis') ||
            s.contains('pending'))) {
      return TxType.purchaseSubmitted;
    }
    if (s == 'submitted' || s == 'purchase_submitted' || s == 'lot_submitted') {
      return TxType.purchaseSubmitted;
    }
    if (s.contains('purchase') && s.contains('valid')) {
      return TxType.purchaseValidated;
    }
    if (s.contains('lot') && s.contains('valid')) {
      return TxType.purchaseValidated;
    }
    if (s.contains('achat') && s.contains('valid')) {
      return TxType.purchaseValidated;
    }
    if (s.contains('validation') &&
        (s.contains('achat') || s.contains('lot') || s.contains('purchase'))) {
      return TxType.purchaseValidated;
    }
    if (s == 'validation' ||
        s == 'validated' ||
        s == 'approved' ||
        s == 'approve' ||
        s == 'purchase_validated' ||
        s == 'lot_validated' ||
        s == 'purchase_validation' ||
        s == 'lot_validation' ||
        s == 'achat_valide' ||
        s == 'achat_validé') {
      return TxType.purchaseValidated;
    }
    if (s == 'rejected' ||
        s == 'reject' ||
        s == 'rejet' ||
        s == 'purchase_rejected' ||
        s == 'lot_rejected' ||
        s == 'purchase_reject' ||
        s == 'lot_reject' ||
        s == 'achat_rejete' ||
        s == 'achat_rejeté') {
      return TxType.purchaseRejected;
    }

    if ((s.contains('qr') || s.contains('code')) &&
        (s.contains('issue') ||
            s.contains('emit') ||
            s.contains('émission') ||
            s.contains('emission'))) {
      return TxType.qrEmission;
    }
    if (s == 'qr_issue') {
      return TxType.qrEmission;
    }

    if (s.contains('wallet') ||
        s.contains('ledger') ||
        s.contains('account_move') ||
        s == 'move' ||
        s == 'wallet_ledger') {
      return TxType.walletLedger;
    }

    if (s.contains('station') || s.contains('consum') || s.contains('use')) {
      return TxType.stationConsumption;
    }

    if (s.contains('qr') &&
        (s.contains('issue') || s.contains('emit') || s.contains('emission'))) {
      return TxType.qrEmission;
    }

    return TxType.walletLedger;
  }

  static bool _isPurchaseValidatedRow(
    Map<String, dynamic> row,
    String typeRaw,
  ) {
    final s = typeRaw.toLowerCase().trim();
    if (s.isNotEmpty) {
      if (s.contains('valid') &&
          (s.contains('lot') ||
              s.contains('purchase') ||
              s.contains('achat'))) {
        return true;
      }
      if (s == 'approved' || s == 'approve') {
        return _has(row, 'purchase_id', 'lot_id') ||
            _has(row, 'purchase_name', 'lot_name');
      }
    }

    final ref = _blob(
      row['name'],
      row['reference'],
      row['display_name'],
      row['label'],
    );
    if (ref.contains('ftx') &&
        (ref.contains('valid') ||
            ref.contains('approv') ||
            ref.contains('achat'))) {
      return true;
    }

    final hasPurchase =
        _has(row, 'purchase_id', 'lot_id') ||
        _has(row, 'purchase_name', 'lot_name');
    final hasQr = _hasAny(row, 'qr_id', 'qr_public_code', 'public_code');
    final hasStation = _has(row, 'station_id', 'station_name');
    if (hasPurchase && !hasQr && !hasStation) {
      return true;
    }
    return false;
  }

  static bool _isPurchaseRejectedRow(Map<String, dynamic> row, String typeRaw) {
    final s = typeRaw.toLowerCase().trim();
    if (s.isNotEmpty) {
      if (s.contains('reject') ||
          s.contains('rejet') ||
          s.contains('cancel') ||
          s.contains('annul')) {
        return _has(row, 'purchase_id', 'lot_id') ||
            _has(row, 'purchase_name', 'lot_name');
      }
      if (s == 'rejected' ||
          s == 'reject' ||
          s == 'purchase_rejected' ||
          s == 'lot_rejected') {
        return _has(row, 'purchase_id', 'lot_id') ||
            _has(row, 'purchase_name', 'lot_name');
      }
    }

    final ref = _blob(
      row['name'],
      row['reference'],
      row['display_name'],
      row['label'],
    );
    if (ref.contains('ftx') &&
        (ref.contains('reject') || ref.contains('rejet'))) {
      return true;
    }

    final state = _blob(row['state'], row['status'], row['move_state']);
    if (state.contains('reject') ||
        state.contains('rejet') ||
        state.contains('cancel') ||
        state.contains('annul')) {
      return _has(row, 'purchase_id', 'lot_id') ||
          _has(row, 'purchase_name', 'lot_name');
    }

    final hasPurchase =
        _has(row, 'purchase_id', 'lot_id') ||
        _has(row, 'purchase_name', 'lot_name');
    final hasQr = _hasAny(row, 'qr_id', 'qr_public_code', 'public_code');
    final hasStation = _has(row, 'station_id', 'station_name');
    return hasPurchase &&
        !hasQr &&
        !hasStation &&
        (_isPurchaseValidatedRow(row, typeRaw) == false) &&
        (ref.contains('reject') || ref.contains('rejet'));
  }

  static bool _isPurchaseSubmittedRow(
    Map<String, dynamic> row,
    String typeRaw,
  ) {
    final s = typeRaw.toLowerCase().trim();
    if (s.isNotEmpty) {
      if (s.contains('submit') ||
          s.contains('soumis') ||
          s.contains('pending') ||
          s == 'submitted' ||
          s == 'purchase_submitted' ||
          s == 'lot_submitted') {
        return _has(row, 'purchase_id', 'lot_id') ||
            _has(row, 'purchase_name', 'lot_name');
      }
    }

    final state = _blob(row['state'], row['status'], row['move_state']);
    if (state.contains('submit') ||
        state.contains('soumis') ||
        state.contains('pending') ||
        state.contains('draft')) {
      return (_has(row, 'purchase_id', 'lot_id') ||
              _has(row, 'purchase_name', 'lot_name')) &&
          !_isPurchaseValidatedRow(row, typeRaw);
    }

    final hasPurchase =
        _has(row, 'purchase_id', 'lot_id') ||
        _has(row, 'purchase_name', 'lot_name');
    final hasQr = _hasAny(row, 'qr_id', 'qr_public_code', 'public_code');
    final hasStation = _has(row, 'station_id', 'station_name');
    return hasPurchase &&
        !hasQr &&
        !hasStation &&
        !_isPurchaseValidatedRow(row, typeRaw);
  }

  static int _rowTotalAmount(Map<String, dynamic> row) {
    for (final k in const [
      'amount_total',
      'total_amount',
      'amount',
      'total',
      'value',
      'mru_total',
      'total_mru',
      'balance',
      'debit',
      'credit',
      'line_amount',
    ]) {
      final v = row[k];
      if (v == null) continue;
      if (v is bool) continue;
      final n = _int(v, -1);
      if (n > 0) return n;
    }

    final nested = row['amount_data'] ?? row['totals'];
    if (nested is Map) {
      final m = Map<String, dynamic>.from(nested);
      for (final k in ['total', 'amount', 'amount_total']) {
        final n = _int(m[k], -1);
        if (n > 0) return n;
      }
    }

    final lines = row['lines'] ?? row['transaction_lines'];
    if (lines is List && lines.isNotEmpty) {
      var sum = 0;
      for (final e in lines) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        var amt = _int(
          m['amount'] ??
              m['subtotal'] ??
              m['line_amount'] ??
              m['total'] ??
              m['value'],
          0,
        );
        final qty = _int(m['qty'] ?? m['quantity'], 0);
        final fv = _int(
          m['face_value'] ?? m['faceValue'] ?? m['unit_value'],
          0,
        );
        if (amt <= 0 && fv > 0 && qty > 0) amt = fv * qty;
        sum += amt;
      }
      if (sum > 0) return sum;
    }

    return 0;
  }

  static List<TransactionLine> _finalizeLines(
    Map<String, dynamic> row,
    List<TransactionLine> lines, {
    DateTime? fallbackExpiration,
  }) {
    if (lines.isEmpty) return lines;

    var normalized = lines.map((l) {
      final expiration = l.expirationDate ?? fallbackExpiration;
      if (l.amount > 0) return l;
      if (l.faceValue > 0 && l.qty > 0) {
        return TransactionLine(
          id: l.id,
          carnetTypeId: l.carnetTypeId,
          carnetTypeCode: l.carnetTypeCode,
          carnetTypeName: l.carnetTypeName,
          faceValue: l.faceValue,
          qty: l.qty,
          amount: l.faceValue * l.qty,
          carnetSize: l.carnetSize,
          expirationDate: expiration,
          lotId: l.lotId,
          faceLineId: l.faceLineId,
          qrId: l.qrId,
        );
      }
      return l;
    }).toList();

    final sum = normalized.fold<int>(0, (s, l) => s + l.amount);
    final rowTotal = _rowTotalAmount(row);
    if (sum > 0) return normalized;
    if (rowTotal <= 0) return normalized;

    if (normalized.length == 1) {
      final l = normalized.first;
      return [
        TransactionLine(
          id: l.id,
          carnetTypeId: l.carnetTypeId,
          carnetTypeCode: l.carnetTypeCode,
          carnetTypeName: l.carnetTypeName,
          faceValue: l.faceValue > 0 ? l.faceValue : rowTotal,
          qty: l.qty > 0 ? l.qty : 1,
          amount: rowTotal,
          expirationDate: l.expirationDate ?? fallbackExpiration,
          lotId: l.lotId,
          faceLineId: l.faceLineId,
          qrId: l.qrId,
        ),
      ];
    }

    final weight = normalized
        .map((l) => l.qty > 0 ? l.qty * (l.faceValue > 0 ? l.faceValue : 1) : 1)
        .toList();
    final totalWeight = weight.fold<int>(0, (a, b) => a + b);
    if (totalWeight <= 0) return normalized;

    var assigned = 0;
    final out = <TransactionLine>[];
    for (var i = 0; i < normalized.length; i++) {
      final l = normalized[i];
      final share = i == normalized.length - 1
          ? rowTotal - assigned
          : (rowTotal * weight[i] / totalWeight).round();
      assigned += share;
      out.add(
        TransactionLine(
          id: l.id,
          carnetTypeId: l.carnetTypeId,
          carnetTypeCode: l.carnetTypeCode,
          carnetTypeName: l.carnetTypeName,
          faceValue: l.faceValue,
          qty: l.qty,
          amount: share,
          carnetSize: l.carnetSize,
          expirationDate: l.expirationDate ?? fallbackExpiration,
          lotId: l.lotId,
          faceLineId: l.faceLineId,
          qrId: l.qrId,
        ),
      );
    }
    return out;
  }

  static List<TransactionLine>? _mapLines(
    Map<String, dynamic> row, {
    DateTime? fallbackExpiration,
  }) {
    final raw =
        row['lines'] ??
        row['transaction_lines'] ??
        row['detail_lines'] ??
        row['purchase_lines'] ??
        row['lignes'];
    if (raw is! List || raw.isEmpty) return null;
    final out = <TransactionLine>[];
    var i = 0;
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final lid = (m['id'] ?? i).toString();
      var fv = _int(
        m['face_value'] ??
            m['faceValue'] ??
            m['unit_value'] ??
            m['nominal'] ??
            m['price_unit'] ??
            m['unit_price'],
        0,
      );
      var qty = _int(m['qty'] ?? m['quantity'] ?? m['product_uom_qty'], 0);
      if (qty <= 0) {
        final carnetQty = _int(m['carnet_qty'], 0);
        final carnetSize = _int(
          m['carnet_size'] ?? m['size'] ?? m['face_count'],
          1,
        ).clamp(1, 9999);
        if (carnetQty > 0) {
          qty = carnetQty * carnetSize;
        }
      }
      if (qty <= 0) continue;
      var amt = _int(
        m['amount'] ??
            m['subtotal'] ??
            m['value'] ??
            m['line_amount'] ??
            m['total'] ??
            m['amount_total'],
        0,
      );
      if (fv <= 0 && amt != 0) {
        fv = (amt / qty).round().abs();
      }
      if (fv <= 0) {
        final unit = _int(m['unit_price'] ?? m['price_unit'], 0);
        if (unit > 0) fv = unit;
      }
      if (fv <= 0) continue;
      if (amt == 0 && fv > 0) amt = fv * qty;
      out.add(
        TransactionLine(
          id: lid,
          carnetTypeId: m['carnet_type_id']?.toString() ?? '',
          carnetTypeCode: m['carnet_type_code']?.toString() ?? '',
          carnetTypeName: m['carnet_type_name']?.toString() ?? '',
          faceValue: fv,
          qty: qty,
          amount: amt,
          carnetSize: _int(m['carnet_size'] ?? m['size'] ?? m['face_count'], 0),
          expirationDate:
              _parseDate(
                m['expiration_date'] ??
                    m['expiry_date'] ??
                    m['expires_at'] ??
                    m['expiresAt'] ??
                    m['expiration'],
              ) ??
              fallbackExpiration,
          lotId: m['lot_id']?.toString(),
          faceLineId: m['face_line_id']?.toString(),
          qrId: m['qr_id']?.toString(),
        ),
      );
      i++;
    }
    return out.isEmpty ? null : out;
  }

  static List<TransactionLine> _syntheticLine(
    Map<String, dynamic> row, {
    required String transactionId,
    DateTime? fallbackExpiration,
  }) {
    final amt = _rowTotalAmount(row);
    var qty = _int(
      row['qty'] ??
          row['quantity'] ??
          row['face_qty'] ??
          row['ticket_qty'] ??
          row['total_qty'],
      0,
    );
    if (qty <= 0) {
      final carnetQty = _int(row['carnet_qty'], 0);
      final carnetSize = _int(
        row['carnet_size'] ?? row['size'] ?? row['face_count'],
        1,
      ).clamp(1, 9999);
      if (carnetQty > 0) qty = carnetQty * carnetSize;
    }
    final fv = _int(
      row['face_value'] ??
          row['faceValue'] ??
          row['unit_value'] ??
          row['nominal'],
      0,
    );
    final useQty = qty > 0 ? qty : 1;
    final useFv = fv > 0 ? fv : (amt > 0 ? (amt / useQty).round().abs() : 0);
    final useAmt = amt > 0 ? amt : (useFv > 0 ? useFv * useQty : 0);

    return [
      TransactionLine(
        id: '$transactionId-0',
        carnetTypeId: _stringField(row, 'carnet_type_id') ?? '',
        carnetTypeCode: _stringField(row, 'carnet_type_code') ?? '',
        carnetTypeName: _stringField(row, 'carnet_type_name') ?? '',
        faceValue: useFv <= 0 ? 1 : useFv,
        qty: useQty,
        amount: useAmt,
        carnetSize: _int(
          row['carnet_size'] ?? row['size'] ?? row['face_count'],
          0,
        ),
        expirationDate:
            _parseDate(
              row['expiration_date'] ??
                  row['expiry_date'] ??
                  row['expires_at'] ??
                  row['expiresAt'] ??
                  row['expiration'],
            ) ??
            fallbackExpiration,
        lotId: _stringField(row, 'lot_id', 'purchase_id'),
        qrId: _stringField(row, 'qr_id'),
      ),
    ];
  }

  static int _int(dynamic v, int d) {
    if (v == null) return d;
    if (v is int) return v;
    if (v is num) return v.round();
    final s = v.toString().trim().replaceAll(',', '.').replaceAll(' ', '');
    if (s.isEmpty) return d;
    return int.tryParse(s.split('.').first) ?? d;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    var parsed = DateTime.tryParse(s.replaceAll(' ', 'T'));
    if (parsed != null) return parsed;

    for (final pattern in [
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm:ss.SSS',
      'yyyy-MM-dd HH:mm:ss.SSSSSS',
      'yyyy-MM-ddTHH:mm:ss',
      'yyyy-MM-ddTHH:mm:ss.SSS',
      'yyyy-MM-ddTHH:mm:ss.SSSSSS',
      'dd/MM/yyyy HH:mm',
      'dd/MM/yyyy HH:mm:ss',
      'dd-MM-yyyy HH:mm:ss',
      'dd-MM-yyyy HH:mm',
      'yyyy-MM-dd',
      'dd/MM/yyyy',
      'dd-MM-yyyy',
    ]) {
      try {
        parsed = DateFormat(pattern).parseStrict(s);
        return parsed;
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
}
