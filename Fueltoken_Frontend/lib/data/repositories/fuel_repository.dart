import 'dart:math';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../models/business_transaction.dart';
import '../models/carnet_type.dart';
import '../models/face_line.dart';
import '../models/purchase_lot.dart';
import '../models/qr_token.dart';
import '../models/station.dart';

/// Dépôt mémoire vide — conservé pour signatures legacy ; données via API ACPEC uniquement.
class FuelRepository {
  FuelRepository._();
  static final FuelRepository instance = FuelRepository._();

  final _uuid = const Uuid();
  final _rng = Random.secure();

  final List<CarnetType> _carnetTypes = [];
  final List<Station> _stations = [];
  final List<PurchaseLot> _lots = [];
  final List<FaceLine> _faceLines = [];
  final List<QrToken> _qrTokens = [];
  final List<BusinessTransaction> _transactions = [];

  // ────────────────────────────── carnet types

  List<CarnetType> listCarnetTypes({bool onlyActive = true}) {
    return _carnetTypes.where((c) => !onlyActive || c.active).toList();
  }

  /// Types « unitaire» (`size == 1`) proposés à l’achat client — issus des données admin, pas du code UI.
  List<CarnetType> listPurchaseOfferTypes({required String companyId}) {
    return _carnetTypes
        .where((c) => c.active && c.companyId == companyId && c.size == 1)
        .toList()
      ..sort((a, b) => a.faceValue.compareTo(b.faceValue));
  }

  CarnetType? carnetTypeById(String id) =>
      _carnetTypes.firstWhereOrNull((c) => c.id == id);

  CarnetType createCarnetType({
    required String code,
    required String name,
    required int size,
    required int faceValue,
    required String companyId,
    required int validityDays,
  }) {
    if (size <= 0 || faceValue <= 0) {
      throw Exception('Taille et valeur nominale doivent être positives.');
    }
    if (validityDays <= 0) {
      throw Exception('La durée de validité doit être positive.');
    }
    final type = CarnetType(
      id: 'ct-${_uuid.v4().substring(0, 6)}',
      code: code,
      name: name,
      size: size,
      faceValue: faceValue,
      companyId: companyId,
      validityDays: validityDays,
    );
    _carnetTypes.add(type);
    return type;
  }

  /// Supprime un type s’il n’apparaît dans aucun lot (soumis ou validé).
  void deleteCarnetType(String id) {
    final used = _lots.any(
      (l) => l.lines.any((ln) => ln.carnetTypeId == id),
    );
    if (used) {
      throw Exception(
        'Ce type est utilisé dans un lot d’achat et ne peut pas être supprimé.',
      );
    }
    final before = _carnetTypes.length;
    _carnetTypes.removeWhere((c) => c.id == id);
    if (_carnetTypes.length == before) {
      throw Exception('Type introuvable.');
    }
  }

  // ────────────────────────────── stations

  List<Station> listStations() => List.unmodifiable(_stations);

  Station? stationById(String id) =>
      _stations.firstWhereOrNull((s) => s.id == id);

  // ────────────────────────────── lots

  List<PurchaseLot> listLots({String? clientId, PurchaseLotState? state}) {
    return _lots.where((l) {
      if (clientId != null && l.clientId != clientId) return false;
      if (state != null && l.state != state) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  PurchaseLot? lotById(String id) =>
      _lots.firstWhereOrNull((l) => l.id == id);

  PurchaseLot submitPurchase({
    required String clientId,
    required String clientName,
    required String companyId,
    required String? paymentProofPath,
    required List<({String carnetTypeId, int carnetCount})> requestLines,
  }) {
    if (paymentProofPath == null || paymentProofPath.isEmpty) {
      throw Exception('La preuve de paiement est obligatoire.');
    }
    if (requestLines.isEmpty) {
      throw Exception('Le lot doit contenir au moins une ligne.');
    }
    final lines = <PurchaseLine>[];
    var maxValidityDays = 1;
    for (final r in requestLines) {
      final ct = carnetTypeById(r.carnetTypeId);
      if (ct == null) throw Exception('Type de ticket introuvable.');
      if (ct.validityDays > maxValidityDays) maxValidityDays = ct.validityDays;
      if (r.carnetCount <= 0) {
        throw Exception('Quantité invalide pour ${ct.code}.');
      }
      lines.add(PurchaseLine(
        id: 'pl-${_uuid.v4().substring(0, 6)}',
        carnetTypeId: ct.id,
        carnetTypeCode: ct.code,
        carnetCount: r.carnetCount,
        carnetSize: ct.size,
        faceValue: ct.faceValue,
      ));
    }
    final year = DateTime.now().year;
    final seq = (_lots.length + 1).toString().padLeft(5, '0');
    final lot = PurchaseLot(
      id: 'lot-${_uuid.v4().substring(0, 6)}',
      internalRef: 'ACH/$year/$seq',
      publicCode: _publicCode(),
      clientId: clientId,
      clientName: clientName,
      companyId: companyId,
      paymentProofPath: paymentProofPath,
      proofs: const [],
      lines: lines,
      state: PurchaseLotState.submitted,
      createdAt: DateTime.now(),
      expirationDate: DateTime.now().add(Duration(days: maxValidityDays)),
    );
    _lots.add(lot);
    return lot;
  }

  /// Admin-only validation. Generates aggregated face lines on approval.
  PurchaseLot validateLot(String lotId, {required String validatorId, required String validatorName}) {
    final idx = _lots.indexWhere((l) => l.id == lotId);
    if (idx < 0) throw Exception('Lot introuvable.');
    final lot = _lots[idx];
    if (lot.state != PurchaseLotState.submitted) {
      throw Exception('Seuls les lots soumis peuvent être validés.');
    }
    final updated = lot.copyWith(
      state: PurchaseLotState.approved,
      validatorId: validatorId,
      validatorName: validatorName,
      validationDate: DateTime.now(),
    );
    _lots[idx] = updated;
    _generateFaceLines(updated);
    _transactions.add(BusinessTransaction(
      id: _uuid.v4(),
      type: TxType.purchaseValidated,
      date: DateTime.now(),
      lotId: updated.id,
      lotInternalRef: updated.internalRef,
      userId: validatorId,
      userName: validatorName,
      lines: [
        for (final l in updated.lines)
          TransactionLine(
            id: _uuid.v4(),
            faceValue: l.faceValue,
            qty: l.faceCount,
            amount: l.lineAmount,
            lotId: updated.id,
          ),
      ],
    ));
    return updated;
  }

  PurchaseLot rejectLot(String lotId, String reason, {required String validatorId, required String validatorName}) {
    final idx = _lots.indexWhere((l) => l.id == lotId);
    if (idx < 0) throw Exception('Lot introuvable.');
    final updated = _lots[idx].copyWith(
      state: PurchaseLotState.rejected,
      rejectionReason: reason,
      validatorId: validatorId,
      validatorName: validatorName,
      validationDate: DateTime.now(),
    );
    _lots[idx] = updated;
    return updated;
  }

  void _generateFaceLines(PurchaseLot lot) {
    final validatedAt = lot.validationDate ?? DateTime.now();
    for (final line in lot.lines) {
      final ct = carnetTypeById(line.carnetTypeId);
      final days = ct?.validityDays ?? 365;
      _faceLines.add(FaceLine(
        id: 'fl-${_uuid.v4().substring(0, 6)}',
        lotId: lot.id,
        lotInternalRef: lot.internalRef,
        purchaseLineId: line.id,
        carnetTypeId: line.carnetTypeId,
        carnetTypeCode: line.carnetTypeCode,
        faceValue: line.faceValue,
        initialQty: line.faceCount,
        availableQty: line.faceCount,
        qrActiveQty: 0,
        qrBlockedQty: 0,
        consumedQty: 0,
        expiredQty: 0,
        expirationDate: validatedAt.add(Duration(days: days)),
        ownerId: lot.clientId,
      ));
    }
  }

  // ────────────────────────────── face lines / wallet

  List<FaceLine> listFaceLines({String? ownerId}) {
    return _faceLines
        .where((f) => ownerId == null || f.ownerId == ownerId)
        .toList()
      ..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
  }

  /// wallet = sum(availableQty × faceValue) over non-expired face lines.
  int walletAmount(String ownerId) {
    return _faceLines
        .where((f) => f.ownerId == ownerId && !f.isExpired)
        .fold(0, (s, f) => s + f.availableQty * f.faceValue);
  }

  /// Aggregation by face value for the dashboard "available" view.
  Map<int, int> availableByFaceValue(String ownerId) {
    final map = <int, int>{};
    for (final f in _faceLines) {
      if (f.ownerId != ownerId || f.isExpired) continue;
      map[f.faceValue] = (map[f.faceValue] ?? 0) + f.availableQty;
    }
    return map;
  }

  // ────────────────────────────── QR emission

  /// Emits a QR for the given { faceValue → qty } request, using FIFO over face lines
  /// (earliest expiration first). Atomic — throws if any line cannot be satisfied.
  QrToken emitQr({
    required String ownerId,
    required String ownerName,
    required String companyId,
    required Map<int, int> request,
  }) {
    if (request.isEmpty || request.values.every((q) => q <= 0)) {
      throw Exception('Demande vide.');
    }

    // Validate availability before mutating.
    for (final entry in request.entries) {
      final faceValue = entry.key;
      final qty = entry.value;
      if (qty <= 0) continue;
      final available = _faceLines
          .where((f) =>
              f.ownerId == ownerId && f.faceValue == faceValue && !f.isExpired)
          .fold<int>(0, (s, f) => s + f.availableQty);
      if (available < qty) {
        throw Exception('Quantité disponible insuffisante.');
      }
    }

    final qrId = 'qr-${_uuid.v4().substring(0, 8)}';
    final qrLines = <QrLine>[];

    for (final entry in request.entries) {
      var remaining = entry.value;
      if (remaining <= 0) continue;

      final candidates = _faceLines
          .where((f) =>
              f.ownerId == ownerId &&
              f.faceValue == entry.key &&
              !f.isExpired &&
              f.availableQty > 0)
          .toList()
        ..sort((a, b) => a.expirationDate.compareTo(b.expirationDate)); // FIFO

      for (final faceLine in candidates) {
        if (remaining == 0) break;
        final take = remaining > faceLine.availableQty
            ? faceLine.availableQty
            : remaining;
        // mutate face line: avail → qrActive
        final i = _faceLines.indexWhere((f) => f.id == faceLine.id);
        _faceLines[i] = faceLine.copyWith(
          availableQty: faceLine.availableQty - take,
          qrActiveQty: faceLine.qrActiveQty + take,
        );
        qrLines.add(QrLine(
          id: 'ql-${_uuid.v4().substring(0, 6)}',
          qrId: qrId,
          lotId: faceLine.lotId,
          lotInternalRef: faceLine.lotInternalRef,
          faceLineId: faceLine.id,
          faceValue: faceLine.faceValue,
          qty: take,
          expirationDate: faceLine.expirationDate,
        ));
        remaining -= take;
      }
    }

    final qr = QrToken(
      id: qrId,
      publicCode: _publicCode(),
      internalRef: 'QR/${DateTime.now().year}/${(_qrTokens.length + 1).toString().padLeft(5, '0')}',
      ownerId: ownerId,
      ownerName: ownerName,
      companyId: companyId,
      state: QrState.active,
      lines: qrLines,
      createdAt: DateTime.now(),
    );
    _qrTokens.add(qr);

    _transactions.add(BusinessTransaction(
      id: _uuid.v4(),
      type: TxType.qrEmission,
      date: DateTime.now(),
      qrId: qr.id,
      qrPublicCode: qr.publicCode,
      userId: ownerId,
      userName: ownerName,
      lines: [
        for (final l in qrLines)
          TransactionLine(
            id: _uuid.v4(),
            faceValue: l.faceValue,
            qty: l.qty,
            amount: l.amount,
            lotId: l.lotId,
            faceLineId: l.faceLineId,
            qrId: qr.id,
          ),
      ],
    ));

    return qr;
  }

  // ────────────────────────────── QR list / lookup

  List<QrToken> listQrs({String? ownerId, QrState? state}) {
    return _qrTokens.where((q) {
      if (ownerId != null && q.ownerId != ownerId) return false;
      if (state != null && q.state != state) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  QrToken? qrById(String id) => _qrTokens.firstWhereOrNull((q) => q.id == id);
  QrToken? qrByPublicCode(String code) =>
      _qrTokens.firstWhereOrNull((q) => q.publicCode == code);

  // ────────────────────────────── QR split (atomic, conservation)

  /// `groups` = list of children. Each child is a list of { qrLineId, qty } picks.
  /// All picks must (a) come from the parent's lines, (b) reference whole faces,
  /// (c) sum to the parent's totals exactly.
  List<QrToken> splitQr({
    required String parentQrId,
    required List<List<({String qrLineId, int qty})>> groups,
    required String userId,
    required String userName,
  }) {
    final parentIdx = _qrTokens.indexWhere((q) => q.id == parentQrId);
    if (parentIdx < 0) throw Exception('QR introuvable.');
    final parent = _qrTokens[parentIdx];
    if (parent.state != QrState.active && parent.state != QrState.blocked) {
      throw Exception('Split interdit pour ce QR.');
    }
    if (groups.isEmpty || groups.every((g) => g.isEmpty)) {
      throw Exception('Le split doit produire au moins un QR enfant.');
    }

    // Build a budget from parent lines
    final budget = <String, int>{for (final l in parent.lines) l.id: l.qty};
    for (final group in groups) {
      for (final pick in group) {
        if (pick.qty <= 0) {
          throw Exception('Quantité invalide dans le split.');
        }
        final remaining = budget[pick.qrLineId];
        if (remaining == null) {
          throw Exception('Ligne QR introuvable dans le parent.');
        }
        if (pick.qty > remaining) {
          throw Exception('Le split dépasse la quantité du parent.');
        }
        budget[pick.qrLineId] = remaining - pick.qty;
      }
    }
    // Conservation: nothing left in budget
    if (budget.values.any((v) => v != 0)) {
      throw Exception('Le split doit répartir toute la valeur du parent.');
    }

    // Build children
    final children = <QrToken>[];
    for (final group in groups) {
      if (group.isEmpty) continue;
      final childId = 'qr-${_uuid.v4().substring(0, 8)}';
      final childLines = <QrLine>[];
      for (final pick in group) {
        final src = parent.lines.firstWhere((l) => l.id == pick.qrLineId);
        childLines.add(QrLine(
          id: 'ql-${_uuid.v4().substring(0, 6)}',
          qrId: childId,
          lotId: src.lotId,
          lotInternalRef: src.lotInternalRef,
          faceLineId: src.faceLineId,
          faceValue: src.faceValue,
          qty: pick.qty,
          expirationDate: src.expirationDate,
        ));
      }
      final allExpired = childLines.every((l) => l.isExpired);
      final hasMix = childLines.any((l) => l.isExpired) &&
          childLines.any((l) => !l.isExpired);
      final state = allExpired
          ? QrState.expired
          : hasMix
              ? QrState.blocked
              : QrState.active;
      children.add(QrToken(
        id: childId,
        publicCode: _publicCode(),
        internalRef: 'QR/${DateTime.now().year}/${(_qrTokens.length + 1 + children.length).toString().padLeft(5, '0')}',
        ownerId: parent.ownerId,
        ownerName: parent.ownerName,
        companyId: parent.companyId,
        state: state,
        parentQrId: parent.id,
        lines: childLines,
        createdAt: DateTime.now(),
      ));
    }

    _qrTokens[parentIdx] = parent.copyWith(state: QrState.split);
    _qrTokens.addAll(children);

    _transactions.add(BusinessTransaction(
      id: _uuid.v4(),
      type: TxType.qrSplit,
      date: DateTime.now(),
      qrId: parent.id,
      qrPublicCode: parent.publicCode,
      userId: userId,
      userName: userName,
      lines: [
        for (final c in children)
          for (final l in c.lines)
            TransactionLine(
              id: _uuid.v4(),
              faceValue: l.faceValue,
              qty: l.qty,
              amount: l.amount,
              lotId: l.lotId,
              faceLineId: l.faceLineId,
              qrId: c.id,
            ),
      ],
      note: '${children.length} QR enfants',
    ));

    return children;
  }

  // ────────────────────────────── station consumption

  /// Atomic full-QR consumption by a station user. Refuses partial / blocked / expired.
  QrToken consumeQr({
    required String publicCode,
    required String stationId,
    required String stationCompanyId,
    required String userId,
    required String userName,
  }) {
    final idx = _qrTokens.indexWhere((q) => q.publicCode == publicCode);
    if (idx < 0) throw Exception('QR introuvable.');
    final qr = _qrTokens[idx];
    if (qr.companyId != stationCompanyId) {
      throw Exception('Station non autorisée pour cette société.');
    }
    if (qr.state == QrState.consumed) {
      throw Exception('QR déjà consommé.');
    }
    if (qr.state == QrState.split) {
      throw Exception('QR remplacé par des QR enfants.');
    }
    if (qr.state == QrState.expired) {
      throw Exception('QR expiré.');
    }
    if (qr.state == QrState.blocked) {
      throw Exception('QR bloqué : split requis.');
    }
    if (qr.lines.any((l) => l.isExpired)) {
      // doctrine: mixed lines → block, do not consume.
      _qrTokens[idx] = qr.copyWith(state: QrState.blocked);
      throw Exception('QR bloqué : split requis.');
    }

    final station = stationById(stationId);
    final consumed = qr.copyWith(
      state: QrState.consumed,
      consumedAt: DateTime.now(),
      consumedByStationId: stationId,
      consumedByStationName: station?.name ?? stationId,
      consumedByUserId: userId,
    );
    _qrTokens[idx] = consumed;

    // Move face line qrActive → consumed
    for (final line in qr.lines) {
      final i = _faceLines.indexWhere((f) => f.id == line.faceLineId);
      if (i < 0) continue;
      final fl = _faceLines[i];
      _faceLines[i] = fl.copyWith(
        qrActiveQty: fl.qrActiveQty - line.qty,
        consumedQty: fl.consumedQty + line.qty,
      );
    }

    _transactions.add(BusinessTransaction(
      id: _uuid.v4(),
      type: TxType.stationConsumption,
      date: DateTime.now(),
      qrId: qr.id,
      qrPublicCode: qr.publicCode,
      stationId: stationId,
      stationName: station?.name,
      userId: userId,
      userName: userName,
      lines: [
        for (final l in qr.lines)
          TransactionLine(
            id: _uuid.v4(),
            faceValue: l.faceValue,
            qty: l.qty,
            amount: l.amount,
            lotId: l.lotId,
            faceLineId: l.faceLineId,
            qrId: qr.id,
          ),
      ],
    ));

    return consumed;
  }

  // ────────────────────────────── transactions

  List<BusinessTransaction> listTransactions({
    String? userId,
    String? stationId,
    String? lotId,
    TxType? type,
  }) {
    return _transactions.where((t) {
      if (userId != null && t.userId != userId) return false;
      if (stationId != null && t.stationId != stationId) return false;
      if (lotId != null && t.lotId != lotId) return false;
      if (type != null && t.type != type) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // ────────────────────────────── helpers

  String _publicCode() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final buf = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buf.write(alphabet[_rng.nextInt(alphabet.length)]);
    }
    return buf.toString();
  }

}
