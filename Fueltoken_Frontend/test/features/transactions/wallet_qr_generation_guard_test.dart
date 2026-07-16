import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wallet shows QR generation as an outgoing movement', () {
    final source = File(
      'lib/features/transactions/screens/transactions_screen.dart',
    ).readAsStringSync();

    final walletTypes = source.substring(
      source.indexOf('static const Set<TxType> _walletTypes'),
      source.indexOf('@override', source.indexOf('_walletTypes')),
    );
    final amountPrefix = source.substring(
      source.indexOf('String _historyAmountPrefix('),
      source.indexOf('class _HistoryFilterChips'),
    );

    expect(walletTypes, contains('TxType.qrEmission'));
    expect(amountPrefix, contains('case TxType.qrEmission:'));
    expect(amountPrefix, contains("return '- ';"));
    expect(
      source,
      contains('(_HistoryQuickFilter.qr, l10n.filterQrGenerations)'),
    );
  });
}
