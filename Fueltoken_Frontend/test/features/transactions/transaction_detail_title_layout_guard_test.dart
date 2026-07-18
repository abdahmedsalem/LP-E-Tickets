import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history and wallet detail cards display titles fully on one line', () {
    final source = File(
      'lib/features/transactions/screens/transactions_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final sharedSource = File(
      'lib/shared/widgets/single_line_card_title.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'SingleLineCardTitle(\n                  text: _lineTypeLabel(l10n)',
      ),
    );
    expect(
      source,
      contains('SingleLineCardTitle(\n                  text: _qrTitle(l10n)'),
    );
    expect(sharedSource, contains('fit: BoxFit.scaleDown'));
    expect(
      sharedSource,
      contains('this.alignment = AlignmentDirectional.centerStart'),
    );
    expect(sharedSource, contains('maxLines: 1'));
    expect(sharedSource, contains('softWrap: false'));
    expect(sharedSource, isNot(contains('TextOverflow.ellipsis')));
  });
}
