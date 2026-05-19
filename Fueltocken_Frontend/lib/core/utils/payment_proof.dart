import 'dart:convert';
import 'dart:typed_data';

/// Décode une preuve encodée en base64 (champ Odoo `proof_data`, etc.).
Uint8List? decodePaymentProofBytes(dynamic value) {
  if (value == null) return null;
  if (value is bool) return null;
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  if (value is List) {
    final bytes = <int>[];
    for (final e in value) {
      if (e is int) {
        bytes.add(e);
      } else if (e is num) {
        bytes.add(e.round());
      } else {
        return null;
      }
    }
    if (bytes.isNotEmpty) return Uint8List.fromList(bytes);
    return null;
  }
  if (value is Map) {
    final m = Map<String, dynamic>.from(value);
    for (final k in [
      'base64',
      'b64',
      'data',
      'content',
      'datas',
      'proof_data',
      'file_data',
      'attachment_data',
      'raw',
    ]) {
      final decoded = decodePaymentProofBytes(m[k]);
      if (decoded != null && decoded.isNotEmpty) return decoded;
    }
    return null;
  }
  final raw = value.toString().trim();
  if (raw.isEmpty ||
      raw.toLowerCase() == 'false' ||
      raw.toLowerCase() == 'true') {
    return null;
  }
  try {
    var payload = raw;
    if (payload.contains(',')) {
      payload = payload.split(',').last;
    }
    payload = payload.replaceAll(RegExp(r'\s+'), '');
    return base64Decode(payload);
  } catch (_) {
    return null;
  }
}

String? mimeTypeFromFilename(String? filename) {
  final n = filename?.toLowerCase().trim() ?? '';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.gif')) return 'image/gif';
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.txt')) return 'text/plain';
  return null;
}

bool isImageMimeType(String? mime, {String? filename}) {
  final m = (mime ?? mimeTypeFromFilename(filename) ?? '').toLowerCase();
  return m.startsWith('image/');
}

bool looksLikeImageFilename(String? filename) {
  final n = filename?.toLowerCase() ?? '';
  return n.endsWith('.png') ||
      n.endsWith('.jpg') ||
      n.endsWith('.jpeg') ||
      n.endsWith('.webp') ||
      n.endsWith('.gif');
}

/// Nom de fichier plausible (évite de confondre `name` Odoo ACH/2026/00001 avec une pièce jointe).
bool looksLikeAttachmentFilename(String? name) {
  final n = name?.trim() ?? '';
  if (n.isEmpty || n == 'false') return false;
  final lower = n.toLowerCase();
  if (lower.contains('.')) {
    return RegExp(
      r'\.(png|jpe?g|webp|gif|pdf|txt|heic|bmp)$',
      caseSensitive: false,
    ).hasMatch(lower);
  }
  return false;
}
