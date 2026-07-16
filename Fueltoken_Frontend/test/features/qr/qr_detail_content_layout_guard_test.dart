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

    expect(titleSource, contains('fit: BoxFit.scaleDown'));
    expect(
      titleSource,
      contains('alignment: AlignmentDirectional.centerStart'),
    );
    expect(titleSource, contains('maxLines: 1'));
    expect(titleSource, contains('softWrap: false'));
    expect(titleSource, isNot(contains('TextOverflow.ellipsis')));
  });
}
