import 'dart:typed_data';

/// Guard frontend aligné avec le backend Patch43K1B.
/// Le backend reste l'autorité ; ce guard sert à éviter une mauvaise UX,
/// un encodage base64 inutile et l'envoi de fichiers refusés.
class PurchasePaymentProofGuard {
  PurchasePaymentProofGuard._();

  static const int maxBytes = 5 * 1024 * 1024;
  static const String maxSizeLabel = '5 Mo';
  static const String invalidMessage =
      'Preuve de paiement invalide. Formats acceptés : JPG, PNG ou PDF, taille maximale 5 Mo.';

  static const List<String> allowedExtensions = <String>[
    'pdf',
    'jpg',
    'jpeg',
    'png',
  ];

  static String normalizedFilename(String? filename) {
    final raw = filename?.trim();
    if (raw == null || raw.isEmpty || raw.toLowerCase() == 'false') {
      return '';
    }
    final slash = raw.lastIndexOf('/');
    // Avoid Python/Dart escaping ambiguity: 0x5C is Windows backslash.
    final backslash = raw.lastIndexOf(String.fromCharCode(0x5C));
    final cut = slash > backslash ? slash : backslash;
    final name = cut >= 0 ? raw.substring(cut + 1).trim() : raw;
    if (name == '.' || name == '..') return '';
    return name;
  }

  static String extensionOf(String? filename) {
    final name = normalizedFilename(filename).toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1);
  }

  static String? validateFileNameAndSize({
    required String? filename,
    required int sizeBytes,
  }) {
    final name = normalizedFilename(filename);
    if (name.isEmpty) return invalidMessage;

    final extension = extensionOf(name);
    if (!allowedExtensions.contains(extension)) return invalidMessage;

    if (sizeBytes <= 0 || sizeBytes > maxBytes) return invalidMessage;

    return null;
  }

  static String? validateBytes({
    required String? filename,
    required Uint8List bytes,
  }) {
    final metadataError = validateFileNameAndSize(
      filename: filename,
      sizeBytes: bytes.length,
    );
    if (metadataError != null) return metadataError;

    final extension = extensionOf(filename);
    final signatureOk = switch (extension) {
      'jpg' || 'jpeg' => _startsWith(bytes, const <int>[0xFF, 0xD8, 0xFF]),
      'png' => _startsWith(bytes, const <int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]),
      'pdf' => _startsWith(bytes, const <int>[0x25, 0x50, 0x44, 0x46, 0x2D]),
      _ => false,
    };

    return signatureOk ? null : invalidMessage;
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }
}
