import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR generation card titles stay complete on one line', () {
    final source = File(
      'lib/features/qr/screens/emit_qr_screen.dart',
    ).readAsStringSync();
    final cardStart = source.indexOf('class _CompositionRowState');
    final cardEnd = source.indexOf('class ', cardStart + 1);
    final cardSource = source.substring(cardStart, cardEnd);

    final titleStart = cardSource.indexOf('widget.title');
    final titleEnd = cardSource.indexOf(
      'const SizedBox(height: 16)',
      titleStart,
    );
    final titleSource = cardSource.substring(titleStart, titleEnd);

    expect(cardSource, contains('SingleLineCardTitle('));
    expect(titleSource, isNot(contains('TextOverflow.ellipsis')));
  });

  test('QR confirmation keeps line title and amount on one row', () {
    final source = File(
      'lib/features/qr/screens/emit_qr_screen.dart',
    ).readAsStringSync();
    final rowStart = source.indexOf('class _EmitConfirmationLineRow');
    final rowEnd = source.indexOf('class _AmountInline', rowStart);
    final rowSource = source.substring(rowStart, rowEnd);

    expect(rowSource, contains('QrGenerationCarnetLine('));

    final lineSource = File(
      'lib/shared/widgets/qr_generation_carnet_line.dart',
    ).readAsStringSync();
    final titleSource = File(
      'lib/shared/widgets/single_line_card_title.dart',
    ).readAsStringSync();
    expect(lineSource, contains('SingleLineCardTitle('));
    expect(titleSource, contains('fit: BoxFit.scaleDown'));
    expect(titleSource, contains('maxLines: 1'));
    expect(titleSource, contains('softWrap: false'));
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
    expect(sectionSource, contains('l10n.usedCarnets'));
    expect(sectionSource, contains('fontSize: 16'));
    expect(sectionSource, contains('fontWeight: FontWeight.w800'));
  });
}
