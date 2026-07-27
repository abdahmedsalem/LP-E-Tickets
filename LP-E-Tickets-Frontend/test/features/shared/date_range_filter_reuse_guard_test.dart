import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('date range component owns date selection and localization', () {
    final source = File(
      'lib/shared/widgets/date_range_filter_bar.dart',
    ).readAsStringSync();

    expect(source, contains('extends StatefulWidget'));
    expect(source, contains('ValueChanged<DateTimeRange> onApply'));
    expect(source, contains('showDatePicker('));
    expect(source, contains('l10n.dateFrom'));
    expect(source, contains('l10n.dateTo'));
    expect(source, contains('l10n.dateApply'));
    expect(source, contains('Formatters.date('));
    expect(source, contains('static const double _controlHeight = 38'));
  });

  test('history, wallet and station reuse the same date filter', () {
    final transactions = File(
      'lib/features/transactions/screens/transactions_screen.dart',
    ).readAsStringSync();
    final wallet = File(
      'lib/features/transactions/screens/wallet_screen.dart',
    ).readAsStringSync();
    final station = File(
      'lib/features/station/screens/station_consumption_history_screen.dart',
    ).readAsStringSync();

    expect(transactions, contains('DateRangeFilterBar('));
    expect(wallet, contains('TransactionsScreenMode.wallet'));
    expect(station, contains('DateRangeFilterBar('));

    for (final source in [transactions, station]) {
      expect(source, isNot(contains('showDatePicker(')));
      expect(source, isNot(contains('_draftFrom')));
      expect(source, isNot(contains('_draftTo')));
      expect(source, isNot(contains('applyColor:')));
    }
  });
}
