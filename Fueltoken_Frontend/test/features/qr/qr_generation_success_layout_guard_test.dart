import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated QR success keeps carnet title and amount on one row', () {
    final source = File(
      'lib/shared/widgets/purchase_submit_success_dialog.dart',
    ).readAsStringSync();
    final rowStart = source.indexOf('class _GeneratedQrLineRow');
    final rowEnd = source.indexOf('class _PurchasedLineRow', rowStart);
    final rowSource = source.substring(rowStart, rowEnd);

    expect(rowSource, contains('QrGenerationCarnetLine('));
    expect(rowSource, isNot(contains('TextOverflow.ellipsis')));

    final sharedSource = File(
      'lib/shared/widgets/qr_generation_carnet_line.dart',
    ).readAsStringSync();
    expect(
      sharedSource,
      contains('alignment: AlignmentDirectional.centerStart'),
    );
    expect(sharedSource, contains('alignment: AlignmentDirectional.centerEnd'));
    expect(sharedSource, contains('const SizedBox(height: 8)'));
  });
}
