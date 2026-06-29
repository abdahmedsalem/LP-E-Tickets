import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Station manual QR code entry guard', () {
    test('manual station screen uses qr_numeric_code for check and use', () {
      final source = File(
        'lib/features/station/screens/station_manual_qr_screen.dart',
      ).readAsStringSync();

      expect(source, contains("'qr_numeric_code'"));
      expect(source, contains('stationQrCheck'));
      expect(source, contains('stationQrUse'));
      expect(source, contains("'action_code'"));
      expect(source, contains("'idempotency_key'"));
      expect(source, isNot(contains('acpec_human_code')));
      expect(source, isNot(contains('human_code')));
      expect(source.toLowerCase(), isNot(contains('fallback')));
    });

    test('station home exposes manual entry as equivalent mode', () {
      final source = File(
        'lib/features/station/screens/station_home_screen.dart',
      ).readAsStringSync();

      expect(source, contains("context.go('/station/manual')"));
      expect(source, contains('Saisir un code manuel'));
      expect(source, contains('Mode équivalent au scan du QR client'));
    });

    test('router exposes station manual route for station role', () {
      final source = File('lib/core/router/app_router.dart').readAsStringSync();

      expect(source, contains("path: '/station/manual'"));
      expect(source, contains('StationManualQrScreen'));
    });
  });
}
