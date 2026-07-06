import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Station manual QR code entry guard', () {
    test('manual station screen uses qr_numeric_code for check and use', () {
      final source = _read(
        'lib/features/station/screens/station_manual_qr_screen.dart',
      );

      expect(source, contains("'qr_numeric_code'"));
      expect(source, contains("'qr_numeric_code': normalized"));
      expect(
        source,
        contains(
          r"final normalized = code.replaceAll(RegExp(r'\D'), '').trim();",
        ),
      );

      final normalizedSource = source.toLowerCase();
      expect(normalizedSource, isNot(contains('fallback du scan')));
      expect(normalizedSource, isNot(contains('mode fallback')));
      expect(normalizedSource, isNot(contains('solution fallback')));
    });

    test(
      'manual station screen displays QR numeric code with human 12 digit format',
      () {
        final source = _read(
          'lib/features/station/screens/station_manual_qr_screen.dart',
        );

        expect(source, contains('_ManualQrCodeInputFormatter'));
        expect(source, contains('1234-5678-9012'));
        expect(source, contains('Format attendu : 1234-5678-9012'));
        expect(
          source,
          contains(r"newValue.text.replaceAll(RegExp(r'\D'), '')"),
        );
        expect(source, contains('substring(0, 12)'));
        expect(source, isNot(contains("hintText: 'Ex. 123456789012'")));
      },
    );
  });
}
