import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR withdrawal cards use the localized backend carnet type name', () {
    final source = File(
      'lib/features/qr/screens/retirer_qr_screen.dart',
    ).readAsStringSync();

    expect(source, contains('line.carnetTypeName'));
    expect(source, contains('fallbackCode: line.carnetTypeCode'));
    expect(source, contains('l10n.ticketsFromCarnet(line.qty, carnetLabel)'));
    expect(source, contains('SingleLineCardTitle('));
    expect(source, isNot(contains('line.carnetSize > 0')));
  });
}
