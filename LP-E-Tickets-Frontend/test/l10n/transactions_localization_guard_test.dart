import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/l10n/app_localizations_ar.dart';

void main() {
  test('history and wallet expose their essential Arabic labels', () {
    final arabic = AppLocalizationsAr();

    expect(arabic.transactionsHistoryTitle, 'سجل العمليات');
    expect(arabic.walletMovementsTitle, 'حركات المحفظة');
    expect(arabic.txTicketTransfer, 'تحويل تذاكر');
    expect(arabic.txTicketReceipt, 'استلام تذاكر');
    expect(arabic.detail, 'التفاصيل');
  });

  test('transaction screens use localized user-facing labels', () {
    final source = File(
      'lib/features/transactions/screens/transactions_screen.dart',
    ).readAsStringSync();
    final dateFilterSource = File(
      'lib/shared/widgets/date_range_filter_bar.dart',
    ).readAsStringSync();

    expect(source, contains('l10n.transactionsHistoryTitle'));
    expect(source, contains('l10n.walletMovementsTitle'));
    expect(source, contains('_transactionTitle(l10n, tx'));
    expect(source, contains('_transactionDetailRows(l10n, tx'));
    expect(source, contains('l10n.filterSentReceived'));
    expect(source, contains('DateRangeFilterBar('));
    expect(dateFilterSource, contains('l10n.dateFrom'));
    expect(dateFilterSource, contains('l10n.dateTo'));
  });
}
