import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/core/utils/purchase_payment_proof_guard.dart';

void main() {
  group('PurchasePaymentProofGuard', () {
    test('accepts PDF, JPEG and PNG signatures under 5 MiB', () {
      final samples = <String, Uint8List>{
        'preuve.pdf': Uint8List.fromList('%PDF-1.4\n'.codeUnits),
        'preuve.jpg': Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1]),
        'preuve.jpeg': Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE1, 1]),
        'preuve.png': Uint8List.fromList(<int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          1,
        ]),
      };

      for (final entry in samples.entries) {
        expect(
          PurchasePaymentProofGuard.validateBytes(
            filename: entry.key,
            bytes: entry.value,
          ),
          isNull,
          reason: entry.key,
        );
      }
    });

    test('rejects WEBP and unknown extensions', () {
      expect(
        PurchasePaymentProofGuard.validateFileNameAndSize(
          filename: 'preuve.webp',
          sizeBytes: 100,
        ),
        PurchasePaymentProofGuard.invalidMessage,
      );
      expect(
        PurchasePaymentProofGuard.validateFileNameAndSize(
          filename: 'preuve.exe',
          sizeBytes: 100,
        ),
        PurchasePaymentProofGuard.invalidMessage,
      );
    });

    test('rejects files larger than 5 MiB before content validation', () {
      expect(
        PurchasePaymentProofGuard.validateFileNameAndSize(
          filename: 'preuve.pdf',
          sizeBytes: PurchasePaymentProofGuard.maxBytes + 1,
        ),
        PurchasePaymentProofGuard.invalidMessage,
      );
    });

    test('rejects signature mismatch even when extension is allowed', () {
      expect(
        PurchasePaymentProofGuard.validateBytes(
          filename: 'preuve.jpg',
          bytes: Uint8List.fromList('%PDF-1.4\n'.codeUnits),
        ),
        PurchasePaymentProofGuard.invalidMessage,
      );
    });

    test('normalizes basename and extension safely', () {
      expect(
        PurchasePaymentProofGuard.normalizedFilename(
          'C:${String.fromCharCode(0x5C)}tmp${String.fromCharCode(0x5C)}preuve.PDF',
        ),
        'preuve.PDF',
      );
      expect(PurchasePaymentProofGuard.extensionOf('preuve.PDF'), 'pdf');
      expect(PurchasePaymentProofGuard.extensionOf('ACH/2026/0001'), '');
    });
  });
}
