import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('client list screens reuse the QR list header and filter styling', () {
    final shared = File(
      'lib/shared/widgets/list_screen_header.dart',
    ).readAsStringSync();
    final carnets = File(
      'lib/features/home/screens/faces_detail_screen.dart',
    ).readAsStringSync();
    final qrs = File(
      'lib/features/qr/screens/qr_list_screen.dart',
    ).readAsStringSync();
    final transactions = File(
      'lib/features/transactions/screens/transactions_screen.dart',
    ).readAsStringSync();

    expect(shared, contains('this.horizontalPadding = 26'));
    expect(shared, contains('this.topPadding = 16'));
    expect(shared, contains('this.titleFilterGap = 18'));
    expect(shared, contains('fontSize: 20'));
    expect(shared, contains('BorderRadius.circular(20)'));
    expect(
      shared,
      contains(
        'padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)',
      ),
    );

    expect(carnets, contains('ListScreenHeader<_CarnetQuickFilter>'));
    expect(qrs, contains('ListScreenHeader<QrState?>'));
    expect(transactions, contains('ListScreenHeader<_HistoryQuickFilter>'));
    expect(transactions, contains('_listHeader(l10n, UserRole.user)'));
    expect(
      RegExp(r'_headerForState\(l10n, user\.role\)').allMatches(transactions),
      hasLength(3),
    );
    expect(transactions, contains('TransactionsScreenMode.wallet'));
  });
}
