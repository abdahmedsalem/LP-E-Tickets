import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR generation success does not display a reference code', () {
    final source = File(
      'lib/shared/widgets/purchase_submit_success_dialog.dart',
    ).readAsStringSync();
    final screenStart = source.indexOf('class QrGenerationSuccessScreen');
    final screenEnd = source.indexOf('class _SuccessScaffold', screenStart);
    final screenSource = source.substring(screenStart, screenEnd);

    expect(screenSource, isNot(contains("label: 'Référence'")));
    expect(screenSource, contains("label: 'Montant total'"));
    expect(screenSource, contains("label: 'Date'"));
  });
}
