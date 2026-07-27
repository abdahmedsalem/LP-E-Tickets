import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('confirmation section titles share the same visual style', () {
    final source = File(
      'lib/shared/widgets/card_section_title.dart',
    ).readAsStringSync();

    expect(source, contains('fontSize: 16'));
    expect(source, contains('fontWeight: FontWeight.w800'));
    expect(source, contains('color: AppColors.ink'));
  });

  test('transfer section label is inside the lines card', () {
    final source = File(
      'lib/features/qr/screens/transfer_confirmation_screen.dart',
    ).readAsStringSync();
    final cardStart = source.indexOf('class _TransferConfirmationLinesCard');
    final cardEnd = source.indexOf('class ', cardStart + 1);
    final cardSource = source.substring(cardStart, cardEnd);

    expect(source, isNot(contains('_TransferConfirmationSectionHeader')));
    expect(cardSource, contains('CardSectionTitle(text: sectionLabel)'));
  });

  test('purchase order and proof labels are inside their cards', () {
    final source = File(
      'lib/features/purchases/screens/purchase_confirmation_screen.dart',
    ).readAsStringSync();
    final linesStart = source.indexOf('class _PurchaseLinesCard');
    final linesEnd = source.indexOf('class ', linesStart + 1);
    final linesSource = source.substring(linesStart, linesEnd);
    final proofStart = source.indexOf('class _PaymentProofImageCard');
    final proofSource = source.substring(proofStart);

    expect(source, isNot(contains('class _SectionHeader')));
    expect(linesSource, contains('CardSectionTitle(text: title)'));
    expect(proofSource, contains('CardSectionTitle(text: title)'));
  });

  test('purchase, transfer and QR lines share size and styles', () {
    final purchaseSource = File(
      'lib/features/purchases/screens/purchase_confirmation_screen.dart',
    ).readAsStringSync();
    final transferSource = File(
      'lib/shared/widgets/transfer_line_row.dart',
    ).readAsStringSync();
    final qrSource = File(
      'lib/shared/widgets/qr_generation_carnet_line.dart',
    ).readAsStringSync();
    final rowSource = File(
      'lib/shared/widgets/confirmation_line_main_row.dart',
    ).readAsStringSync();
    final stylesSource = File(
      'lib/shared/widgets/confirmation_line_styles.dart',
    ).readAsStringSync();

    for (final source in [purchaseSource, transferSource, qrSource]) {
      expect(source, contains('ConfirmationLineMainRow('));
    }
    expect(rowSource, contains('static const double height = 20'));
    expect(rowSource, contains('flex: 8'));
    expect(rowSource, contains('flex: 2'));
    expect(rowSource, contains('flex: 3'));
    expect(rowSource, contains('ConfirmationLineStyles.title'));
    expect(rowSource, contains('ConfirmationLineStyles.amountValue'));
    expect(rowSource, contains('ConfirmationLineStyles.amountUnit'));
    expect(stylesSource, contains('fontSize: 15'));
    expect(stylesSource, contains('fontWeight: FontWeight.w700'));
    expect(stylesSource, contains('fontWeight: FontWeight.w800'));
  });
}
