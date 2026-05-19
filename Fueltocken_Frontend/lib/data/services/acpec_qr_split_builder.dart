import '../models/qr_token.dart';

/// Erreur métier lors de la construction du payload `qr/split`.
class AcpecQrSplitException implements Exception {
  AcpecQrSplitException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Construit le corps `POST …/mobile/qr/split` (conservation des quantités).
///
/// Doctrine (PDF FuelToken § I) :
/// - répartition par **ticket** (face entière) + lot d’origine ;
/// - somme des parties = QR parent ;
/// - QR `blocked` ou multi-lignes : `qr_line_id` sur chaque ligne enfant ;
/// - QR `active` homogène (une ligne technique) : `face_value` + `qty`.
class AcpecQrSplitBuilder {
  AcpecQrSplitBuilder._();

  static Map<String, int> _lineBudget(QrToken parent) =>
      {for (final l in parent.lines) l.id: l.qty};

  /// Totaux parent par valeur faciale (MRU).
  static Map<int, int> parentTotalsByFace(QrToken parent) {
    final map = <int, int>{};
    for (final l in parent.lines) {
      map[l.faceValue] = (map[l.faceValue] ?? 0) + l.qty;
    }
    return map;
  }

  /// Tickets déjà affectés par identifiant de ligne parent.
  static Map<String, int> usedByLineId(
    Iterable<Map<String, int>> partitions,
  ) {
    final map = <String, int>{};
    for (final part in partitions) {
      part.forEach((lineId, v) {
        map[lineId] = (map[lineId] ?? 0) + v;
      });
    }
    return map;
  }

  /// Synthèse par valeur faciale (affichage).
  static Map<int, int> usedByFaceFromPartitions(
    QrToken parent,
    Iterable<Map<String, int>> partitions,
  ) {
    final map = <int, int>{};
    final usedLines = usedByLineId(partitions);
    for (final l in parent.lines) {
      final n = usedLines[l.id] ?? 0;
      if (n <= 0) continue;
      map[l.faceValue] = (map[l.faceValue] ?? 0) + n;
    }
    return map;
  }

  static int totalTickets(QrToken parent) =>
      parent.lines.fold(0, (s, l) => s + l.qty);

  static int assignedTickets(Iterable<Map<String, int>> partitions) =>
      usedByLineId(partitions).values.fold(0, (s, v) => s + v);

  static bool isComplete(QrToken parent, List<Map<String, int>> partitions) {
    if (assignedTickets(partitions) <= 0) return false;
    if (assignedTickets(partitions) != totalTickets(parent)) return false;

    final budget = _lineBudget(parent);
    final used = usedByLineId(partitions);
    for (final e in budget.entries) {
      if ((used[e.key] ?? 0) != e.value) return false;
    }

    final nonEmpty = partitions.where((p) => p.values.any((v) => v > 0)).length;
    return nonEmpty >= 2;
  }

  /// Nombre de tickets valides / expirés sur le parent (QR bloqué).
  static ({int valid, int expired}) ticketExpiryCounts(QrToken parent) {
    var valid = 0;
    var expired = 0;
    for (final l in parent.lines) {
      if (l.isExpired) {
        expired += l.qty;
      } else {
        valid += l.qty;
      }
    }
    return (valid: valid, expired: expired);
  }

  /// Répartition initiale en 2 parties (par ligne / lot).
  static List<Map<String, int>> evenSplitTwoPartitions(QrToken parent) {
    final a = <String, int>{};
    final b = <String, int>{};
    for (final l in parent.lines) {
      final half = l.qty ~/ 2;
      final rest = l.qty - half;
      if (half > 0) a[l.id] = half;
      if (rest > 0) b[l.id] = rest;
    }
    return [a, b];
  }

  static bool canSplitParent(QrToken parent) =>
      parent.state == QrState.active || parent.state == QrState.blocked;

  static bool parentRequiresLineIds(QrToken parent) {
    if (parent.state == QrState.blocked) return true;
    return parent.lines.length > 1;
  }

  static int? qrLineIdForApi(QrLine line) {
    for (final raw in [line.id, line.faceLineId]) {
      final n = int.tryParse(raw.trim());
      if (n != null) return n;
    }
    return null;
  }

  static List<QrLine> sortedParentLines(QrToken parent) {
    final list = List<QrLine>.from(parent.lines);
    list.sort((a, b) {
      if (parent.state == QrState.blocked) {
        final ae = a.isExpired ? 1 : 0;
        final be = b.isExpired ? 1 : 0;
        if (ae != be) return ae.compareTo(be);
      }
      final lot = a.lotInternalRef.compareTo(b.lotInternalRef);
      if (lot != 0) return lot;
      if (a.faceValue != b.faceValue) return a.faceValue.compareTo(b.faceValue);
      return a.expirationDate.compareTo(b.expirationDate);
    });
    return list;
  }

  /// Quantité encore disponible pour une ligne parent (toutes parties).
  static int remainingOnLine(
    QrToken parent,
    List<Map<String, int>> partitions,
    String lineId,
  ) {
    final cap = parent.lines
        .where((l) => l.id == lineId)
        .fold(0, (s, l) => s + l.qty);
    final used = usedByLineId(partitions)[lineId] ?? 0;
    return cap - used;
  }

  /// Max assignable à [partitionIndex] pour [lineId].
  static int maxForPartitionLine(
    QrToken parent,
    List<Map<String, int>> partitions,
    int partitionIndex,
    String lineId,
  ) {
    final cap = parent.lines
        .where((l) => l.id == lineId)
        .fold(0, (s, l) => s + l.qty);
    var usedElsewhere = 0;
    for (var i = 0; i < partitions.length; i++) {
      if (i == partitionIndex) continue;
      usedElsewhere += partitions[i][lineId] ?? 0;
    }
    return cap - usedElsewhere;
  }

  /// Payload `children` — sélection explicite par ligne parent (lot / carnet).
  static List<Map<String, dynamic>> buildChildrenPayload({
    required QrToken parent,
    required List<Map<String, int>> partitionLinePicks,
  }) {
    if (!isComplete(parent, partitionLinePicks)) {
      throw AcpecQrSplitException(
        'Répartissez exactement tous les tickets du QR parent entre au moins deux parties.',
      );
    }

    final requireLineIds = parentRequiresLineIds(parent);
    final budget = _lineBudget(parent);
    final out = <Map<String, dynamic>>[];

    for (final picks in partitionLinePicks) {
      if (!picks.values.any((v) => v > 0)) continue;

      final lines = <Map<String, dynamic>>[];
      for (final entry in picks.entries) {
        final qty = entry.value;
        if (qty <= 0) continue;

        final line = parent.lines.cast<QrLine?>().firstWhere(
              (l) => l?.id == entry.key,
              orElse: () => null,
            );
        if (line == null) {
          throw AcpecQrSplitException('Ligne QR parent introuvable.');
        }
        if (qty > (budget[line.id] ?? 0)) {
          throw AcpecQrSplitException(
            'Quantité invalide pour ${line.faceValue} MRU (lot ${line.lotInternalRef}).',
          );
        }

        if (requireLineIds) {
          final lid = qrLineIdForApi(line);
          if (lid == null) {
            throw AcpecQrSplitException(
              'Identifiant de ligne QR manquant — rechargez le détail du QR.',
            );
          }
          lines.add({
            'face_value': line.faceValue,
            'qty': qty,
            'qr_line_id': lid,
          });
        } else {
          final existing = lines.indexWhere(
            (r) => r['face_value'] == line.faceValue,
          );
          if (existing >= 0) {
            lines[existing]['qty'] =
                (lines[existing]['qty'] as int) + qty;
          } else {
            lines.add({
              'face_value': line.faceValue,
              'qty': qty,
            });
          }
        }
        budget[line.id] = budget[line.id]! - qty;
      }

      if (lines.isNotEmpty) {
        out.add({'lines': lines});
      }
    }

    if (out.length < 2) {
      throw AcpecQrSplitException(
        'Le partage doit créer au moins deux QR avec des tickets.',
      );
    }

    for (final left in budget.values) {
      if (left > 0) {
        throw AcpecQrSplitException(
          'Tous les tickets du parent doivent être répartis (conservation).',
        );
      }
    }

    return out;
  }

  /// Allocation démo locale ([FuelRepository.splitQr]).
  static List<List<({String qrLineId, int qty})>> demoAllocationGroups({
    required QrToken parent,
    required List<Map<String, int>> partitionLinePicks,
  }) {
    buildChildrenPayload(
      parent: parent,
      partitionLinePicks: partitionLinePicks,
    );

    final groups = <List<({String qrLineId, int qty})>>[];
    for (final picks in partitionLinePicks) {
      if (!picks.values.any((v) => v > 0)) continue;
      final group = <({String qrLineId, int qty})>[];
      picks.forEach((lineId, qty) {
        if (qty > 0) group.add((qrLineId: lineId, qty: qty));
      });
      if (group.isNotEmpty) groups.add(group);
    }
    return groups;
  }

  static Map<String, dynamic> buildSplitRequest({
    required QrToken parent,
    required List<Map<String, int>> partitionLinePicks,
    required String idempotencyKey,
  }) {
    return {
      'public_code': parent.publicCode,
      'children': buildChildrenPayload(
        parent: parent,
        partitionLinePicks: partitionLinePicks,
      ),
      'idempotency_key': idempotencyKey,
    };
  }
}
