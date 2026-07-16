import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR confirmation keeps line title and amount on one row', () {
    final source = File(
      'lib/features/qr/screens/emit_qr_screen.dart',
    ).readAsStringSync();
    final rowStart = source.indexOf('class _EmitConfirmationLineRow');
    final rowEnd = source.indexOf('class _AmountInline', rowStart);
    final rowSource = source.substring(rowStart, rowEnd);

    expect(rowSource, contains('QrGenerationCarnetLine('));

    final sharedSource = File(
      'lib/shared/widgets/qr_generation_carnet_line.dart',
    ).readAsStringSync();
    expect(sharedSource, contains('fit: BoxFit.scaleDown'));
    expect(sharedSource, contains('maxLines: 1'));
    expect(sharedSource, contains('softWrap: false'));
  });

  test('QR confirmation displays Carnets utilisés inside the lines card', () {
    final source = File(
      'lib/features/qr/screens/emit_qr_screen.dart',
    ).readAsStringSync();
    final sectionStart = source.indexOf('class _EmitConfirmationLinesSection');
    final sectionEnd = source.indexOf(
      'class _EmitConfirmationTotalRow',
      sectionStart,
    );
    final sectionSource = source.substring(sectionStart, sectionEnd);

    expect(source, isNot(contains("title: 'Tickets à générer'")));
    expect(sectionSource, contains("'Carnets utilisés'"));
    expect(sectionSource, contains('fontSize: 16'));
    expect(sectionSource, contains('fontWeight: FontWeight.w800'));
  });
}
