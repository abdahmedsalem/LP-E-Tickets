import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('StationQrCheckResult guard', () {
    test('client name never falls back to technical QR name', () {
      final source = _read('lib/data/models/station_qr_check_result.dart');

      expect(source, contains('client_name'));
      expect(source, contains('partner_name'));
      expect(source, isNot(contains("      'name',")));
    });
  });
}
