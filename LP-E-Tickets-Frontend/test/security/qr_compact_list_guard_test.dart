import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QR compact list guard', () {
    test(
      'QR list uses public code for navigation and never secret/internal refs',
      () {
        final source = File(
          'lib/features/qr/screens/qr_list_screen.dart',
        ).readAsStringSync();

        expect(source, isNot(contains('qr.qrNumericCode')));
        expect(source, isNot(contains('_formatQrNumericCode')));
        expect(source, isNot(contains('qr.internalRef')));
        expect(source, contains('qr.publicCode.trim().isNotEmpty'));
        expect(source, contains('Uri.encodeComponent(qr.publicCode)'));
        expect(source, isNot(contains('Code numérique indisponible')));
      },
    );
  });
}
