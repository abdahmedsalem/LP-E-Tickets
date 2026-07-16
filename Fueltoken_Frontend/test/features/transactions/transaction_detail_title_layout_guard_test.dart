import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history and wallet detail cards display titles fully on one line', () {
    final source = File(
      'lib/features/transactions/screens/transactions_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final widgetStart = source.indexOf('class _TxLineTitle');
    final widgetEnd = source.indexOf(
      'List<_TxDetailRow> _transactionDetailRows',
      widgetStart,
    );
    final widgetSource = source.substring(widgetStart, widgetEnd);

    expect(
      source,
      contains('_TxLineTitle(\n                  title: _lineTypeLabel(l10n)'),
    );
    expect(
      source,
      contains('_TxLineTitle(\n                  title: _qrTitle(l10n)'),
    );
    expect(widgetSource, contains('fit: BoxFit.scaleDown'));
    expect(
      widgetSource,
      contains('alignment: AlignmentDirectional.centerStart'),
    );
    expect(widgetSource, contains('maxLines: 1'));
    expect(widgetSource, contains('softWrap: false'));
    expect(widgetSource, isNot(contains('TextOverflow.ellipsis')));
  });
}
