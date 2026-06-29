import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QR compact list guard', () {
    test('QR list uses compact rows instead of QR visual cards', () {
      final source = File(
        'lib/features/qr/screens/qr_list_screen.dart',
      ).readAsStringSync();

      expect(source, contains('ListView.separated'));
      expect(source, contains('_QrCompactListTile'));
      expect(source, contains('Expire dès'));
      expect(source, contains('StatusBadge.qr'));
      expect(source, isNot(contains('GridView.builder')));
      expect(source, isNot(contains('QrImageView')));
    });

    test('QR list displays formatted numeric QR code', () {
      final source = File(
        'lib/features/qr/screens/qr_list_screen.dart',
      ).readAsStringSync();

      expect(source, contains('qr.qrNumericCode'));
      expect(source, contains('_formatQrNumericCode'));
      expect(source, contains("digits.length != 12"));
      expect(source, contains("substring(0, 4)"));
      expect(source, contains("substring(4, 8)"));
      expect(source, contains("substring(8, 12)"));
      expect(source, contains('Code numérique indisponible'));
    });

    test('QR list keeps detail navigation by public code', () {
      final source = File(
        'lib/features/qr/screens/qr_list_screen.dart',
      ).readAsStringSync();

      expect(source, contains("context.push('/qr/\$seg')"));
      expect(source, contains('Uri.encodeComponent(qr.publicCode)'));
    });
  });
}
