import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated QR success keeps carnet title and amount on one row', () {
    final source = File(
      'lib/features/qr/generation/screens/qr_generation_success_screen.dart',
    ).readAsStringSync();
    final rowStart = source.indexOf('class _GeneratedQrLineRow');
    final rowEnd = source.indexOf('\n  }\n}', rowStart);
    final rowSource = source.substring(rowStart, rowEnd);

    expect(rowSource, contains('QrGenerationCarnetLine('));
    expect(rowSource, isNot(contains('TextOverflow.ellipsis')));

    final sharedSource = File(
      'lib/shared/widgets/qr_generation_carnet_line.dart',
    ).readAsStringSync();
    final rowLayoutSource = File(
      'lib/shared/widgets/confirmation_line_main_row.dart',
    ).readAsStringSync();
    expect(sharedSource, contains('ConfirmationLineMainRow('));
    expect(rowLayoutSource, contains('height: height'));
    expect(rowLayoutSource, contains('flex: 8'));
    expect(rowLayoutSource, contains('flex: 3'));
    expect(sharedSource, contains('const SizedBox(height: 8)'));
  });
}
