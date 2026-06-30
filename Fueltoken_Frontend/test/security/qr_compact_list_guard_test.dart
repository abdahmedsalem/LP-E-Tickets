import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QR compact list guard', () {
    test(
      'QR list displays non-sensitive QR reference, not manual numeric code',
      () {
        final source = File(
          'lib/features/qr/screens/qr_list_screen.dart',
        ).readAsStringSync();

        expect(source, isNot(contains('qr.qrNumericCode')));
        expect(source, isNot(contains('_formatQrNumericCode')));
        expect(source, contains('qr.internalRef'));
        expect(source, contains('Référence QR indisponible'));
        expect(source, isNot(contains('Code numérique indisponible')));
      },
    );
  });
}
