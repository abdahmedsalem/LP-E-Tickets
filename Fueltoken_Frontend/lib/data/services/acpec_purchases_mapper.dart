import '../../core/config/odoo_api_config.dart';
import '../../core/utils/payment_proof.dart';
import '../../core/utils/rejection_reason.dart';
import '../models/purchase_lot.dart';
import '../models/acpec_purchase_create_result.dart';

/// Mappe la réponse JSON-RPC de la liste des achats mobile vers [PurchaseLot].
///
/// Tolère plusieurs formes : `data` liste, `{ data: { items|purchases|… } }`, clés à la racine, etc.
class AcpecPurchasesMapper {
  AcpecPurchasesMapper._();

  static final DateTime _fallbackDate = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  /// Réponse de création de commande (`purchase_id`, `public_code`, `state`).
  static AcpecPurchaseCreateResult parseCreateResult(dynamic raw) {
    if (raw is! Map) {
      throw Exception('Réponse serveur invalide.');
    }
    var m = Map<String, dynamic>.from(raw);
    if (m['ok'] == false) {
      throw Exception(
        m['message']?.toString() ?? 'Création de la commande refusée.',
      );
    }
    if (m['data'] is Map) {
      final d = Map<String, dynamic>.from(m['data'] as Map);
      if (d['ok'] == false) {
        throw Exception(
          d['message']?.toString() ?? 'Création de la commande refusée.',
        );
      }
      m = d;
    }

    final pid = (m['purchase_id'] ?? m['id'] ?? m['order_id'])
        ?.toString()
        .trim();
    if (pid == null || pid.isEmpty) {
      throw Exception(
        'Réponse incomplète : identifiant de commande (purchase_id) manquant.',
      );
    }
    final pub =
        (m['public_code'] ?? m['publicCode'] ?? m['public_reference'])
            ?.toString()
            .trim() ??
        '';
    if (pub.isEmpty) {
      throw Exception(
        'Réponse incomplète : code public (public_code) manquant.',
      );
    }
    final st = (m['state'] ?? m['status'] ?? 'submitted').toString().trim();
    final payRef = m['payment_reference']?.toString().trim();
    return AcpecPurchaseCreateResult(
      purchaseId: pid,
      publicCode: pub,
      state: st.isEmpty ? 'submitted' : st,
      paymentReference: (payRef != null && payRef.isNotEmpty) ? payRef : null,
    );
  }

  static List<PurchaseLot> fromRpcResult(
    dynamic raw, {
    required String clientId,
    required String clientName,
    required String companyId,
  }) {
    if (raw is List) {
      return _mapLotsFromItems(
        raw,
        clientId: clientId,
        clientName: clientName,
        companyId: companyId,
      );
    }
    if (raw is! Map) {
      throw Exception('Réponse liste des lots invalide.');
    }
    final top = Map<String, dynamic>.from(raw);
    if (top['ok'] == false) {
      throw Exception(
        top['message']?.toString() ?? 'Liste des lots indisponible.',
      );
    }

    final d = top['data'];
    if (d is List) {
      return _mapLotsFromItems(
        d,
        clientId: clientId,
        clientName: clientName,
        companyId: companyId,
      );
    }

    Map<String, dynamic> data = top;
    if (d is Map) {
      data = Map<String, dynamic>.from(d);
      if (data['ok'] == false) {
        throw Exception(
          data['message']?.toString() ?? 'Liste des lots indisponible.',
        );
      }
    }

    var items = _itemsList(data);
    if (items.isEmpty) {
      items = _itemsList(top);
    }
    return _mapLotsFromItems(
      items,
      clientId: clientId,
      clientName: clientName,
      companyId: companyId,
    );
  }

  static List<PurchaseLot> _mapLotsFromItems(
    List<dynamic> items, {
    required String clientId,
    required String clientName,
    required String companyId,
  }) {
    final out = <PurchaseLot>[];
    for (final e in items) {
      if (e is! Map) continue;
      final row = Map<String, dynamic>.from(e);
      final lot = _mapLot(
        row,
        clientId: clientId,
        clientName: clientName,
        companyId: companyId,
      );
      if (lot != null) out.add(lot);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  static List<dynamic> _itemsList(Map<String, dynamic> data) {
    for (final key in [
      'items',
      'purchases',
      'achats',
      'lots',
      'records',
      'orders',
      'results',
    ]) {
      final v = data[key];
      if (v is List) return v;
    }
    return const [];
  }

  /// Identifiant numérique pour `purchase_id` (route, liste admin, etc.).
  ///
  /// Évite d’extraire le premier groupe de chiffres dans une UUID ou un libellé
  /// (ex. `550e8400-…` ou `ACH/2026/00001`) : dans ce cas on ne retient que
  /// un suffixe numérique clair après séparateur, sinon null.
  static int? resolvePurchaseId(String routeId) {
    final t = routeId.trim();
    if (t.isEmpty) return null;
    final direct = int.tryParse(t);
    if (direct != null && direct > 0) return direct;
    final hasNonDigitSep = RegExp(r'[a-zA-Z_/\\-]').hasMatch(t);
    if (hasNonDigitSep) {
      final tail = RegExp(r'(?:^|[/_-])(\d+)\s*$').firstMatch(t);
      if (tail != null) {
        final parsed = int.tryParse(tail.group(1)!);
        if (parsed != null && parsed > 0) return parsed;
      }
      return null;
    }
    final match = RegExp(r'(\d+)').firstMatch(t);
    if (match == null) return null;
    final parsed = int.tryParse(match.group(1)!);
    if (parsed != null && parsed > 0) return parsed;
    return null;
  }

  static String? _scalarId(dynamic raw) {
    if (raw == null) return null;
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first != null) {
        final s = first.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Lève si la réponse approve/reject indique un échec (`ok: false`).
  static void assertAdminActionOk(
    dynamic raw, {
    String fallback = 'Action refusée par le serveur.',
  }) {
    if (raw == null) return;
    if (raw is bool) {
      if (!raw) throw Exception(fallback);
      return;
    }
    if (raw is String) {
      final lower = raw.trim().toLowerCase();
      if (lower == 'false' || lower == '0') {
        throw Exception(fallback);
      }
      return;
    }
    if (raw is! Map) return;

    void checkEnvelope(Map<String, dynamic> m) {
      if (m['ok'] == false) {
        throw Exception(m['message']?.toString() ?? fallback);
      }
      if (m['success'] == false) {
        throw Exception(
          m['message']?.toString() ??
              m['error']?.toString() ??
              m['detail']?.toString() ??
              fallback,
        );
      }
      final err = m['error'];
      if (err is String && err.trim().isNotEmpty) {
        throw Exception(err.trim());
      }
      if (err is Map && err.isNotEmpty) {
        throw Exception(err['message']?.toString() ?? fallback);
      }
      final status = m['status']?.toString().toLowerCase().trim();
      if (status == 'error' || status == 'failed') {
        throw Exception(m['message']?.toString() ?? fallback);
      }
    }

    final m = Map<String, dynamic>.from(raw);
    checkEnvelope(m);
    final data = m['data'];
    if (data is Map) {
      checkEnvelope(Map<String, dynamic>.from(data));
    }
    final result = m['result'];
    if (result is Map) {
      checkEnvelope(Map<String, dynamic>.from(result));
    }
  }

  static String? _resolveProofFilename(Map<String, dynamic> p) {
    for (final key in [
      'filename',
      'file_name',
      'original_filename',
      'proof_filename',
      'nom_fichier',
    ]) {
      final v = p[key]?.toString().trim();
      if (v != null && v.isNotEmpty && v != 'false') return v;
    }
    final name = p['name']?.toString().trim();
    if (looksLikeAttachmentFilename(name)) return name;
    final nom = p['nom']?.toString().trim();
    if (looksLikeAttachmentFilename(nom)) return nom;
    return null;
  }

  static bool _mapHasProofPayload(Map<String, dynamic> m) {
    for (final k in [
      'proof_data',
      'proof_content',
      'payment_proof_data',
      'donnees',
      'fichier',
      'contenu',
      'datas',
      'attachment_data',
      'file_data',
      'image_data',
      'binary',
      'base64',
    ]) {
      if (decodePaymentProofBytes(m[k]) != null) return true;
    }
    for (final k in [
      'preuves',
      'proofs',
      'attachments',
      'payment_proofs',
      'documents',
      'attachment_list',
      'proof_ids',
      'preuve_ids',
      'attachment_ids',
      'message_attachment_ids',
      'payment_proof',
      'proof',
      'preuve_paiement',
      'preuve',
    ]) {
      final v = m[k];
      if (v is List && v.isNotEmpty) return true;
      if (v is Map && v.isNotEmpty) return true;
      if (v is String && decodePaymentProofBytes(v) != null) return true;
    }
    for (final k in [
      'proof_attachment_id',
      'payment_proof_attachment_id',
      'payment_proof_id',
      'proof_id',
      'attachment_id',
      'message_main_attachment_id',
      'ir_attachment_id',
    ]) {
      final id = _scalarId(m[k]);
      if (id != null && id != '0') return true;
    }
    final url = m['url'] ?? m['download_url'] ?? m['href'] ?? m['link'];
    if (url != null && url.toString().trim().isNotEmpty && url != false) {
      return true;
    }
    return looksLikeAttachmentFilename(_resolveProofFilename(m));
  }

  static bool _isMeaningfulProof(PurchaseProofSummary p) => p.isDisplayable;

  static int _proofQuality(PurchaseProofSummary p) {
    if (p.bytes != null && p.bytes!.isNotEmpty) return 3;
    if (p.url != null && p.url!.isNotEmpty) return 2;
    if (looksLikeAttachmentFilename(p.filename)) return 1;
    return 0;
  }

  /// Détail d’un achat (route mobile ou admin selon le contexte).
  static PurchaseLot parsePurchaseDetail(
    dynamic raw, {
    required String clientId,
    required String clientName,
    required String companyId,
    int? requestedPurchaseId,
  }) {
    final payload = _unwrapDetailPayload(
      raw,
      requestedPurchaseId: requestedPurchaseId,
    );
    var lot = _mapLot(
      payload,
      clientId: clientId,
      clientName: clientName,
      companyId: companyId,
    );
    if (lot == null) {
      throw Exception(
        'Détail achat incomplet : identifiant ou données manquants côté serveur.',
      );
    }
    final mergedProofs = _collectProofsFromDetail(raw, payload);
    if (mergedProofs.isNotEmpty) {
      lot = lot.copyWith(proofs: mergedProofs);
    }
    return lot;
  }

  /// Rassemble les preuves depuis le payload fusionné et toute l’enveloppe JSON.
  static List<PurchaseProofSummary> _collectProofsFromDetail(
    dynamic raw,
    Map<String, dynamic> payload,
  ) {
    final seen = <String>{};
    final out = <PurchaseProofSummary>[];

    void addAll(List<PurchaseProofSummary> list) {
      for (final p in list) {
        if (!_isMeaningfulProof(p)) continue;
        final sig =
            '${p.filename ?? ''}|${p.bytes?.length ?? 0}|${p.url ?? ''}';
        final existing = out.indexWhere(
          (e) =>
              '${e.filename ?? ''}|${e.bytes?.length ?? 0}|${e.url ?? ''}' ==
              sig,
        );
        if (existing >= 0) {
          if (_proofQuality(p) > _proofQuality(out[existing])) {
            out[existing] = p;
          }
          continue;
        }
        if (seen.add(sig)) out.add(p);
      }
    }

    addAll(_proofsFromRow(payload));
    addAll(_proofsFromDeepScan(raw));

    if (raw is Map) {
      final root = Map<String, dynamic>.from(raw);
      addAll(_proofsFromRow(root));
      final d = root['data'];
      if (d is Map) {
        final dm = Map<String, dynamic>.from(d);
        addAll(_proofsFromRow(dm));
        final inner = dm['result'];
        if (inner is Map) {
          addAll(_proofsFromRow(Map<String, dynamic>.from(inner)));
        }
      }
      final topResult = root['result'];
      if (topResult is Map) {
        addAll(_proofsFromRow(Map<String, dynamic>.from(topResult)));
      }
    }

    return out;
  }

  /// Fusionne `data`, objet `purchase` / `achat` et listes sœurs (`lines`, `preuves`, …).
  static Map<String, dynamic> _unwrapDetailPayload(
    dynamic raw, {
    int? requestedPurchaseId,
  }) {
    if (raw is! Map) {
      throw Exception('Réponse détail achat invalide.');
    }
    var root = Map<String, dynamic>.from(raw);
    if (root['ok'] == false) {
      throw Exception(
        root['message']?.toString() ?? 'Détail de l’achat indisponible.',
      );
    }

    Map<String, dynamic> envelope = root;
    final d = root['data'];
    if (d is Map) {
      envelope = Map<String, dynamic>.from(d);
      if (envelope['ok'] == false) {
        throw Exception(
          envelope['message']?.toString() ?? 'Détail de l’achat indisponible.',
        );
      }
    } else if (d is List && d.isNotEmpty && d.first is Map) {
      envelope = Map<String, dynamic>.from(d.first as Map);
    }

    if (envelope['result'] is Map) {
      envelope = Map<String, dynamic>.from(envelope['result'] as Map);
    }

    Map<String, dynamic>? nested;
    for (final key in [
      'purchase',
      'achat',
      'lot',
      'order',
      'record',
      'purchase_order',
      'item',
    ]) {
      final v = envelope[key];
      if (v is Map) {
        nested = Map<String, dynamic>.from(v);
        break;
      }
    }

    final merged = nested != null
        ? Map<String, dynamic>.from(nested)
        : Map<String, dynamic>.from(envelope);

    if (merged['id'] == null && merged['purchase_id'] == null) {
      final po = envelope['purchase_order_id'] ?? root['purchase_order_id'];
      final pid = _scalarId(po);
      if (pid != null) merged['purchase_id'] = pid;
    }

    void adoptList(String target, List<String> keys) {
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
      'purchase_lines',
      'line_ids',
      'order_lines',
      'order_line',
      'order_line_ids',
    ]);
    adoptList('preuves', [
      'preuves',
      'proofs',
      'attachments',
      'payment_proofs',
      'documents',
      'attachment_list',
      'ir_attachments',
      'attachment_ids',
      'proof_ids',
      'preuve_ids',
      'payment_proof_ids',
      'message_attachment_ids',
      'pieces_jointes',
      'justificatifs',
    ]);
    if (merged['preuves'] == null) {
      for (final source in [envelope, root]) {
        for (final key in [
          'proof_ids',
          'preuve_ids',
          'attachment_ids',
          'message_attachment_ids',
        ]) {
          final v = source[key];
          if (v is List && v.isNotEmpty) {
            merged['preuves'] = v;
            break;
          }
        }
        if (merged['preuves'] != null) break;
      }
    }
    _adoptProofField(merged, envelope, root);

    for (final proofKey in [
      'payment_proof',
      'proof',
      'preuve_paiement',
      'preuve',
    ]) {
      final v = envelope[proofKey] ?? root[proofKey];
      if (v is Map && merged[proofKey] == null) {
        merged[proofKey] = v;
      }
    }

    for (final k in [
      'rejection_reason',
      'reject_reason',
      'motif_rejet',
      'rejection_message',
      'payment_reference',
      'payment_proof_path',
      'proof_path',
      'proof_filename',
      'proof_data',
      'proof_content',
      'proof_mimetype',
      'proof_mime_type',
      'state',
      'status',
      'public_code',
      'name',
      'create_date',
      'created_at',
      'validation_date',
      'validated_at',
      'expiration_date',
      'expiry_date',
      'amount_total',
      'total_amount',
      'face_qty_total',
      'total_faces',
      'partner_id',
      'client_id',
      'client_name',
      'partner_name',
    ]) {
      if (merged[k] == null && envelope[k] != null) {
        merged[k] = envelope[k];
      }
      if (merged[k] == null && root[k] != null) {
        merged[k] = root[k];
      }
    }

    if (merged['id'] == null &&
        merged['purchase_id'] == null &&
        merged['lot_id'] == null) {
      var pid = requestedPurchaseId ?? 0;
      if (pid <= 0) pid = _int(envelope['purchase_id'], 0);
      if (pid <= 0) pid = _int(root['purchase_id'], 0);
      if (pid > 0) merged['purchase_id'] = pid;
    }

    return merged;
  }

  /// `preuves` peut être une liste, un objet unique, ou une chaîne base64.
  static void _adoptProofField(
    Map<String, dynamic> merged,
    Map<String, dynamic> envelope,
    Map<String, dynamic> root,
  ) {
    if (merged['preuves'] is List && (merged['preuves'] as List).isNotEmpty) {
      return;
    }

    for (final source in [merged, envelope, root]) {
      for (final key in [
        'preuves',
        'proofs',
        'attachments',
        'payment_proofs',
        'documents',
      ]) {
        final v = source[key];
        if (v is List && v.isNotEmpty) {
          merged['preuves'] = v;
          return;
        }
        if (v is Map) {
          merged['preuves'] = [v];
          return;
        }
        if (v is String) {
          final bytes = decodePaymentProofBytes(v);
          if (bytes != null && bytes.isNotEmpty) {
            merged['preuves'] = [
              {
                'proof_data': v,
                'proof_filename': source['proof_filename'] ?? 'preuve.jpg',
              },
            ];
            return;
          }
        }
      }
    }
  }

  static PurchaseProofSummary? _proofFromAttachmentTuple(
    List<dynamic> tuple, {
    required int index,
  }) {
    final id = tuple.isNotEmpty ? tuple[0] : null;
    final name = tuple.length > 1 ? tuple[1]?.toString().trim() : null;
    final map = <String, dynamic>{};
    if (id != null) map['id'] = id;
    if (name?.isNotEmpty == true) map['filename'] = name;
    if (tuple.length > 2) {
      map['proof_data'] = tuple[2];
    }
    return _proofFromMap(map, fallbackLabel: 'Preuve ${index + 1}');
  }

  static PurchaseProofSummary? _proofFromAttachmentId(
    num id, {
    required int index,
  }) {
    return _proofFromMap({
      'id': id,
    }, fallbackLabel: 'Pièce jointe ${index + 1}');
  }

  static PurchaseProofSummary? _proofFromMap(
    Map<String, dynamic> p, {
    required String fallbackLabel,
  }) {
    final filename = _resolveProofFilename(p);
    final mime =
        (p['mimetype'] ??
                p['mime_type'] ??
                p['type_mime'] ??
                p['proof_mimetype'] ??
                p['proof_mime_type'])
            ?.toString()
            .trim();
    final resolvedMime = (mime != null && mime.isNotEmpty)
        ? mime
        : mimeTypeFromFilename(filename);

    final bytes = decodePaymentProofBytes(
      p['proof_data'] ??
          p['proof_content'] ??
          p['payment_proof_data'] ??
          p['donnees'] ??
          p['fichier'] ??
          p['contenu'] ??
          p['image'] ??
          p['image_data'] ??
          p['file'] ??
          p['binary'] ??
          p['base64'] ??
          p['b64'] ??
          p['content_base64'] ??
          p['file_base64'] ??
          p['image_base64'] ??
          p['proof_base64'] ??
          p['data'] ??
          p['content'] ??
          p['file_data'] ??
          p['datas'] ??
          p['attachment_data'],
    );

    var url =
        (p['url'] ??
                p['download_url'] ??
                p['href'] ??
                p['link'] ??
                p['public_url'])
            ?.toString()
            .trim();
    final attachId = _scalarId(
      p['id'] ?? p['attachment_id'] ?? p['ir_attachment_id'],
    );
    if ((url == null || url.isEmpty || url == 'false') &&
        attachId != null &&
        attachId != '0') {
      final base = OdooApiConfig.baseUrlTrimmed;
      if (base.isNotEmpty) {
        url = '$base/web/content/$attachId?download=true';
      }
    }
    final hasUrl = url != null && url.isNotEmpty && url != 'false';
    final hasBytes = bytes != null && bytes.isNotEmpty;
    final hasName =
        filename != null && filename.isNotEmpty && filename != 'false';

    if (!hasBytes && !hasUrl && !hasName) return null;

    final title = p['title'] ?? p['type'];
    final label =
        (title?.toString().trim().isNotEmpty == true
            ? title!.toString().trim()
            : null) ??
        (hasName ? filename : null) ??
        fallbackLabel;

    return PurchaseProofSummary(
      label: label,
      filename: hasName ? filename : null,
      url: hasUrl ? url : null,
      mimeType: resolvedMime,
      uploadedAt: _parseDate(
        p['create_date'] ?? p['upload_date'] ?? p['date'] ?? p['written_date'],
      ),
      bytes: hasBytes ? bytes : null,
    );
  }

  static List<PurchaseProofSummary> _proofsFromRow(Map<String, dynamic> row) {
    final out = <PurchaseProofSummary>[];
    final raw =
        row['preuves'] ??
        row['proofs'] ??
        row['attachments'] ??
        row['payment_proofs'] ??
        row['documents'] ??
        row['attachment_list'];
    if (raw is Map) {
      final single = _proofFromMap(
        Map<String, dynamic>.from(raw),
        fallbackLabel: 'Preuve de paiement',
      );
      if (single != null) out.add(single);
    } else if (raw is String) {
      final bytes = decodePaymentProofBytes(raw);
      if (bytes != null && bytes.isNotEmpty) {
        out.add(
          PurchaseProofSummary(
            label: 'Preuve de paiement',
            filename: 'preuve.jpg',
            mimeType: 'image/jpeg',
            bytes: bytes,
          ),
        );
      }
    } else if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final e = raw[i];
        if (e is Map) {
          final proof = _proofFromMap(
            Map<String, dynamic>.from(e),
            fallbackLabel: 'Document ${i + 1}',
          );
          if (proof != null) out.add(proof);
        } else if (e is List && e.length >= 2) {
          final proof = _proofFromAttachmentTuple(e, index: i);
          if (proof != null) out.add(proof);
        } else if (e is String) {
          final bytes = decodePaymentProofBytes(e);
          if (bytes != null && bytes.isNotEmpty) {
            out.add(
              PurchaseProofSummary(
                label: 'Preuve ${i + 1}',
                filename: 'preuve_${i + 1}.jpg',
                mimeType: 'image/jpeg',
                bytes: bytes,
              ),
            );
          }
        } else if (e is num) {
          final proof = _proofFromAttachmentId(e, index: i);
          if (proof != null) out.add(proof);
        }
      }
    }

    for (final key in ['payment_proof', 'proof', 'preuve_paiement', 'preuve']) {
      final nested = row[key];
      if (nested is Map) {
        final proof = _proofFromMap(
          Map<String, dynamic>.from(nested),
          fallbackLabel: 'Preuve de paiement',
        );
        if (proof != null) out.add(proof);
      }
    }

    out.addAll(_proofsFromAttachmentIdFields(row));

    PurchaseProofSummary? embedded;
    if (_mapHasProofPayload(row)) {
      embedded = _proofFromMap(row, fallbackLabel: 'Preuve de paiement');
      if (embedded != null && _isMeaningfulProof(embedded)) {
        final dup = out.any(
          (p) =>
              p.bytes != null &&
              embedded!.bytes != null &&
              p.bytes!.length == embedded.bytes!.length,
        );
        if (!dup) out.insert(0, embedded);
      }
    }

    final fn = row['proof_filename']?.toString().trim();
    if (fn != null &&
        fn.isNotEmpty &&
        fn != 'false' &&
        out.isEmpty &&
        embedded == null) {
      final rowBytes = decodePaymentProofBytes(row['proof_data']);
      out.add(
        PurchaseProofSummary(
          label: 'Preuve de paiement',
          filename: fn,
          mimeType: mimeTypeFromFilename(fn),
          bytes: rowBytes,
        ),
      );
    }
    return out.where(_isMeaningfulProof).toList();
  }

  static List<PurchaseProofSummary> _proofsFromAttachmentIdFields(
    Map<String, dynamic> row,
  ) {
    final out = <PurchaseProofSummary>[];
    var index = 0;
    final sharedFilename = row['proof_filename']?.toString().trim();

    for (final key in [
      'proof_attachment_id',
      'payment_proof_attachment_id',
      'payment_proof_id',
      'proof_id',
      'attachment_id',
      'message_main_attachment_id',
    ]) {
      final id = _scalarId(row[key]);
      if (id == null || id == '0') continue;
      final proof = _proofFromMap({
        'id': id,
        if (sharedFilename != null &&
            sharedFilename.isNotEmpty &&
            sharedFilename != 'false')
          'filename': sharedFilename,
      }, fallbackLabel: 'Preuve de paiement');
      if (proof != null && _isMeaningfulProof(proof)) {
        out.add(proof);
        index++;
      }
    }

    for (final key in [
      'proof_ids',
      'preuve_ids',
      'attachment_ids',
      'message_attachment_ids',
    ]) {
      final v = row[key];
      if (v is! List) continue;
      for (final e in v) {
        if (e is Map) {
          final proof = _proofFromMap(
            Map<String, dynamic>.from(e),
            fallbackLabel: 'Preuve ${index + 1}',
          );
          if (proof != null && _isMeaningfulProof(proof)) out.add(proof);
        } else if (e is List && e.length >= 2) {
          final proof = _proofFromAttachmentTuple(e, index: index);
          if (proof != null && _isMeaningfulProof(proof)) out.add(proof);
        } else if (e is num) {
          final proof = _proofFromAttachmentId(e, index: index);
          if (proof != null && _isMeaningfulProof(proof)) out.add(proof);
        }
        index++;
      }
    }
    return out;
  }

  /// Parcourt toute la réponse JSON pour retrouver des preuves encodées.
  static List<PurchaseProofSummary> _proofsFromDeepScan(dynamic node) {
    final seen = <String>{};
    final out = <PurchaseProofSummary>[];

    void walk(dynamic n) {
      if (n is Map) {
        final m = Map<String, dynamic>.from(n);
        if (_mapHasProofPayload(m)) {
          final proof = _proofFromMap(m, fallbackLabel: 'Preuve de paiement');
          if (proof != null && _isMeaningfulProof(proof)) {
            final sig =
                '${proof.filename ?? ''}|${proof.bytes?.length ?? 0}|${proof.url ?? ''}';
            if (seen.add(sig)) out.add(proof);
          }
        }
        for (final v in m.values) {
          walk(v);
        }
      } else if (n is List) {
        for (final e in n) {
          walk(e);
        }
      }
    }

    walk(node);
    return out;
  }

  static PurchaseLot? _mapLot(
    Map<String, dynamic> row, {
    required String clientId,
    required String clientName,
    required String companyId,
  }) {
    final id = _scalarId(
      row['id'] ??
          row['purchase_id'] ??
          row['lot_id'] ??
          row['order_id'] ??
          row['purchase_order_id'],
    );
    if (id == null || id == '0') return null;

    var resClientId = clientId;
    var resClientName = clientName;
    final cidRow = row['client_id']?.toString().trim();
    if (cidRow != null && cidRow.isNotEmpty) {
      resClientId = cidRow;
    }
    final partner = row['partner_id'];
    if (partner is List && partner.isNotEmpty) {
      resClientId = partner[0]?.toString().trim() ?? resClientId;
      if (partner.length > 1 && partner[1] != null) {
        final pn = partner[1].toString().trim();
        if (pn.isNotEmpty) resClientName = pn;
      }
    } else if (partner != null && partner.toString().trim().isNotEmpty) {
      resClientId = partner.toString().trim();
    }
    for (final k in [
      'client_name',
      'partner_name',
      'buyer_name',
      'customer_name',
    ]) {
      final v = row[k]?.toString().trim();
      if (v != null && v.isNotEmpty) {
        resClientName = v;
        break;
      }
    }

    final internalRef =
        row['name']?.toString() ?? row['internal_ref']?.toString() ?? 'Lot $id';
    final publicCode =
        row['public_code']?.toString() ?? row['publicCode']?.toString() ?? '';
    final state = _parseState(
      (row['state'] ?? row['status'])?.toString() ?? '',
    );
    final submittedAt = _parseDate(row['submitted_at'] ?? row['submittedAt']);
    final approvedAt = _parseDate(row['approved_at'] ?? row['approvedAt']);
    final rejectedAt = _parseDate(row['rejected_at'] ?? row['rejectedAt']);

    final proofs = _proofsFromRow(row);
    final paymentRef = row['payment_reference']?.toString().trim();
    final String? paymentProofPath =
        row['payment_proof_path']?.toString() ?? row['proof_path']?.toString();

    final lines =
        _mapLines(row['lines']) ??
        _mapLines(row['lignes']) ??
        _mapLines(row['purchase_lines']) ??
        _syntheticLinesFromTotals(row);

    final createdAt =
        _parseDate(
          row['create_date'] ??
              row['created_at'] ??
              row['date_order'] ??
              row['created'] ??
              row['date'],
        ) ??
        _fallbackDate;

    final exp =
        _parseDate(row['expiration_date'] ?? row['expiry_date']) ??
        createdAt.add(const Duration(days: 365));

    return PurchaseLot(
      id: id,
      internalRef: internalRef,
      publicCode: publicCode,
      clientId: resClientId,
      clientName: resClientName,
      companyId: companyId,
      paymentProofPath:
          paymentProofPath ??
          (proofs.isNotEmpty ? proofs.first.filename : null),
      paymentReference: (paymentRef != null && paymentRef.isNotEmpty)
          ? paymentRef
          : null,
      proofs: proofs,
      lines: lines,
      state: state,
      validatorId: row['validator_id']?.toString(),
      validatorName: row['validator_name']?.toString(),
      submittedAt: submittedAt,
      approvedAt: approvedAt,
      rejectedAt: rejectedAt,
      validationDate: _parseDate(row['validation_date'] ?? row['validated_at']),
      rejectionReason: rejectionReasonFromMap(row),
      createdAt: createdAt,
      expirationDate: exp,
    );
  }

  static List<PurchaseLine>? _mapLines(dynamic v) {
    if (v is! List || v.isEmpty) return null;
    final out = <PurchaseLine>[];
    var i = 0;
    for (final e in v) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final lineId = (m['id'] ?? i).toString();
      final ctId = (m['carnet_type_id'] ?? m['type_id'] ?? m['product_id'] ?? 0)
          .toString();
      final code =
          m['carnet_type_code']?.toString() ??
          m['carnet_code']?.toString() ??
          m['code']?.toString() ??
          (m['carnet_type_name']?.toString().isNotEmpty == true
              ? m['carnet_type_name'].toString()
              : null) ??
          'T$ctId';
      final name =
          m['carnet_type_name']?.toString().trim() ??
          m['name']?.toString().trim() ??
          '';
      final carnetQty = _int(m['carnet_qty'] ?? m['qty'] ?? m['quantity'], 0);
      final size = _int(
        m['carnet_size'] ?? m['size'] ?? m['face_count'],
        1,
      ).clamp(1, 9999);
      final fv = _int(
        m['face_value'] ?? m['nominal'] ?? m['price_unit'] ?? m['unit_price'],
        0,
      );
      if (carnetQty <= 0 && fv <= 0) continue;
      out.add(
        PurchaseLine(
          id: 'pl-$lineId',
          carnetTypeId: ctId,
          carnetTypeCode: code,
          carnetTypeName: name,
          carnetCount: carnetQty > 0 ? carnetQty : 1,
          carnetSize: size,
          faceValue: fv > 0 ? fv : 1,
        ),
      );
      i++;
    }
    return out.isEmpty ? null : out;
  }

  /// Quand le serveur ne renvoie que des totaux (`amount_total`, `face_qty_total`).
  static List<PurchaseLine> _syntheticLinesFromTotals(
    Map<String, dynamic> row,
  ) {
    final faceQty = _int(
      row['face_qty_total'] ?? row['face_qty'] ?? row['total_faces'],
      0,
    );
    final amount = _double(row['amount_total'] ?? row['total_amount']);
    if (faceQty <= 0 && amount <= 0) {
      return const [];
    }
    if (faceQty > 0) {
      final unit = (amount / faceQty).round().clamp(1, 999999999);
      return [
        PurchaseLine(
          id: 'pl-syn-${row['id']}',
          carnetTypeId: '0',
          carnetTypeCode: '—',
          carnetTypeName: '',
          carnetCount: faceQty,
          carnetSize: 1,
          faceValue: unit,
        ),
      ];
    }
    final amt = amount.round().clamp(1, 999999999);
    return [
      PurchaseLine(
        id: 'pl-syn-${row['id']}',
        carnetTypeId: '0',
        carnetTypeCode: '—',
        carnetTypeName: '',
        carnetCount: 1,
        carnetSize: 1,
        faceValue: amt,
      ),
    ];
  }

  static PurchaseLotState _parseState(String raw) {
    final s = raw.toLowerCase().trim();
    switch (s) {
      case 'draft':
      case 'brouillon':
        return PurchaseLotState.draft;
      case 'submitted':
      case 'pending':
      case 'waiting':
      case 'sent':
        return PurchaseLotState.submitted;
      case 'approved':
      case 'validated':
      case 'done':
      case 'sale':
        return PurchaseLotState.approved;
      case 'rejected':
      case 'cancel':
      case 'cancelled':
        return PurchaseLotState.rejected;
      default:
        return PurchaseLotState.submitted;
    }
  }

  static int _int(dynamic v, int d) {
    if (v == null) return d;
    if (v is int) return v;
    if (v is num) return v.round();
    final s = v.toString().trim().replaceAll(',', '.');
    if (s.isEmpty) return d;
    return int.tryParse(s.split('.').first) ?? d;
  }

  static double _double(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final parsed = DateTime.tryParse(s);
    if (parsed != null) return parsed;

    final asInt = int.tryParse(s);
    if (asInt != null && asInt > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(
        asInt > 1000000000000 ? asInt : asInt * 1000,
        isUtc: true,
      );
    }

    return null;
  }
}
