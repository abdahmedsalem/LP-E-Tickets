import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR generation success does not display a reference code', () {
    final source = File(
      'lib/features/qr/generation/screens/qr_generation_success_screen.dart',
    ).readAsStringSync();
    final screenStart = source.indexOf('class QrGenerationSuccessScreen');
    final screenEnd = source.indexOf(
      'class _GeneratedQrLinesSection',
      screenStart,
    );
    final screenSource = source.substring(screenStart, screenEnd);

    expect(screenSource, isNot(contains("label: 'Référence'")));
    expect(screenSource, contains('label: l10n.totalAmount'));
    expect(screenSource, contains('label: l10n.date'));
  });
}
