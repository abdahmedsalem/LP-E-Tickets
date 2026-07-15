import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR generation hides its action bar when no carnet is available', () {
    final source = File(
      'lib/features/qr/screens/emit_qr_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final hasEntries = availableLines.isNotEmpty;'));
    expect(source, contains('bottomNavigationBar: hasEntries'));
    expect(source, contains(': null,'));
  });
}
