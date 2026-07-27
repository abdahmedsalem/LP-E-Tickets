import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR detail content displays each title fully on one line', () {
    final source = File(
      'lib/features/qr/screens/qr_detail_screen.dart',
    ).readAsStringSync();
    final rowStart = source.indexOf('class _CompositionLineRow');
    final rowSource = source.substring(rowStart);
    final titleEnd = rowSource.indexOf('AmountInline(');
    final titleSource = rowSource.substring(0, titleEnd);
    final sharedSource = File(
      'lib/shared/widgets/single_line_card_title.dart',
    ).readAsStringSync();

    expect(titleSource, contains('SingleLineCardTitle('));
    expect(sharedSource, contains('fit: BoxFit.scaleDown'));
    expect(
      sharedSource,
      contains('this.alignment = AlignmentDirectional.centerStart'),
    );
    expect(sharedSource, contains('maxLines: 1'));
    expect(sharedSource, contains('softWrap: false'));
    expect(titleSource, isNot(contains('TextOverflow.ellipsis')));
  });

  test('QR detail content uses the localized carnet type name', () {
    final frontendSource = File(
      'lib/features/qr/screens/qr_detail_screen.dart',
    ).readAsStringSync();
    final rowStart = frontendSource.indexOf('class _CompositionLineRow');
    final rowSource = frontendSource.substring(rowStart);
    final backendSource = File(
      '../LP-E-Tickets-Backend/addons/acpec_fueltoken_api/controllers/api_mobile.py',
    ).readAsStringSync();

    expect(rowSource, contains('final localizedLabel = label.trim();'));
    expect(rowSource, isNot(contains("RegExp(r'^\\s*Carnet")));
    expect(
      backendSource,
      contains("'carnet_type_name': self._carnet_type_label("),
    );
  });
}
