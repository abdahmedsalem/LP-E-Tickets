import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR withdrawal always keeps at least one source line', () {
    final source = File(
      'lib/features/qr/screens/retirer_qr_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_wouldWithdrawAllLines(parent, nextSelection)'));
    expect(
      RegExp(
        r'_wouldWithdrawAllLines\(parent, _selectedLineIds\)',
      ).allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(source, contains('l10n.qrKeepAtLeastOneLine'));
  });
}
