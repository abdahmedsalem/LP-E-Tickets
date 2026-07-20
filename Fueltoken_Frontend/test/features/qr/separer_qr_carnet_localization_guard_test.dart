import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR separation cards use the localized backend carnet type name', () {
    final source = File(
      'lib/features/qr/screens/separer_qr_screen.dart',
    ).readAsStringSync();

    expect(source, contains('line.carnetTypeName'));
    expect(source, contains('fallbackCode: line.carnetTypeCode'));
    expect(source, contains('l10n.ticketsFromCarnet(line.qty, carnetLabel)'));
    expect(source, contains('SingleLineCardTitle('));
    expect(source, isNot(contains('Formatters.carnetTypeLabel(')));
  });
}
