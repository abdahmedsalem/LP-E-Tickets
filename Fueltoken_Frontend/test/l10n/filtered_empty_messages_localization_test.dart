import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';

void main() {
  test(
    'filtered empty messages include the selected filter in both locales',
    () {
      final french = lookupAppLocalizations(const Locale('fr'));
      final arabic = lookupAppLocalizations(const Locale('ar'));

      expect(french.filteredEmptyTitle('Expirés'), contains('Expirés'));
      expect(
        french.carnetsFilteredEmptyMessage('Disponibles'),
        contains('Disponibles'),
      );
      expect(french.qrsFilteredEmptyMessage('Bloqués'), contains('Bloqués'));
      expect(
        french.historyFilteredEmptyMessage('Commandes'),
        contains('Commandes'),
      );
      expect(
        french.walletFilteredEmptyMessage('Réceptions'),
        contains('Réceptions'),
      );

      expect(
        arabic.filteredEmptyTitle(arabic.filterExpired),
        contains(arabic.filterExpired),
      );
      expect(
        arabic.carnetsFilteredEmptyMessage(arabic.filterAvailable),
        contains(arabic.filterAvailable),
      );
      expect(
        arabic.qrsFilteredEmptyMessage(arabic.qrFilterBlocked),
        contains(arabic.qrFilterBlocked),
      );
      expect(
        arabic.historyFilteredEmptyMessage(arabic.filterOrders),
        contains(arabic.filterOrders),
      );
      expect(
        arabic.walletFilteredEmptyMessage(arabic.filterReceipts),
        contains(arabic.filterReceipts),
      );
    },
  );

  test('all four client lists use filter-aware empty messages', () {
    final carnets = File(
      'lib/features/home/screens/faces_detail_screen.dart',
    ).readAsStringSync();
    final qrs = File(
      'lib/features/qr/screens/qr_list_screen.dart',
    ).readAsStringSync();
    final transactions = File(
      'lib/features/transactions/screens/transactions_screen.dart',
    ).readAsStringSync();

    expect(carnets, contains('l10n.carnetsFilteredEmptyMessage'));
    expect(qrs, contains('l10n.qrsFilteredEmptyMessage'));
    expect(transactions, contains('l10n.historyFilteredEmptyMessage'));
    expect(transactions, contains('l10n.walletFilteredEmptyMessage'));
  });
}
