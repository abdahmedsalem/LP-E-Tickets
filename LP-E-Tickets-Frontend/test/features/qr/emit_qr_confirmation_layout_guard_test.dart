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
    final titleEnd = cardSource.indexOf('Align(', titleStart);
    final titleSource = cardSource.substring(titleStart, titleEnd);

    expect(cardSource, contains('SingleLineCardTitle('));
    expect(titleSource, isNot(contains('TextOverflow.ellipsis')));
  });

  test('QR generation card expiration date is never truncated', () {
    final source = File(
      'lib/features/qr/screens/emit_qr_screen.dart',
    ).readAsStringSync();
    final cardStart = source.indexOf('class _CompositionRowState');
    final cardEnd = source.indexOf('class ', cardStart + 1);
    final cardSource = source.substring(cardStart, cardEnd);
    final dateStart = cardSource.indexOf('_expirationLabel(l10n),');
    expect(dateStart, greaterThan(0));
    final dateEnd = cardSource.indexOf('const SizedBox(height: 5)', dateStart);
    final dateSource = cardSource.substring(dateStart, dateEnd);

    expect(dateSource, isNot(contains('TextOverflow.ellipsis')));
    expect(dateSource, isNot(contains('maxLines: 1')));
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
    final sharedRowSource = File(
      'lib/shared/widgets/confirmation_line_main_row.dart',
    ).readAsStringSync();
    expect(lineSource, contains('ConfirmationLineMainRow('));
    expect(sharedRowSource, contains('SingleLineCardTitle('));
    expect(sharedRowSource, contains('static const double height = 20'));
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
    expect(sectionSource, contains('CardSectionTitle(text: l10n.usedCarnets)'));
  });
}
