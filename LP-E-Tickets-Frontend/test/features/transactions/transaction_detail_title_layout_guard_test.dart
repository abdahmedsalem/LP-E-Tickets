import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history and wallet cards use a taller shared header', () {
    final source = File(
      'lib/features/transactions/screens/transactions_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('padding: const EdgeInsets.fromLTRB(10, 16, 10, 16)'),
    );
    final cardStart = source.indexOf('class _TxCardState');
    final cardEnd = source.indexOf('class _TxDetailBody', cardStart);
    final cardSource = source.substring(cardStart, cardEnd);
    expect(cardSource, contains('const SizedBox(height: 12)'));
    expect(
      cardSource,
      contains('crossAxisAlignment: CrossAxisAlignment.center'),
    );
  });

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
