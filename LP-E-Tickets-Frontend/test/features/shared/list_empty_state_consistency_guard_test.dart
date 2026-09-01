import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dynamic list screens use the shared EmptyState component', () {
    final listScreens = <String>[
      'lib/features/purchases/screens/purchases_list_screen.dart',
      'lib/features/purchases/screens/submit_purchase_screen.dart',
      'lib/features/transactions/screens/transactions_screen.dart',
      'lib/features/station/screens/station_consumption_history_screen.dart',
      'lib/features/qr/screens/qr_list_screen.dart',
      'lib/features/qr/screens/emit_qr_screen.dart',
      'lib/features/qr/screens/transfer_carnets_screen.dart',
      'lib/features/qr/screens/transfer_tickets_screen.dart',
      'lib/features/home/screens/faces_detail_screen.dart',
      'lib/features/settings/screens/notifications_screen.dart',
      'lib/features/settings/screens/acpec_connection_step1_screen.dart',
      'lib/shared/widgets/wallet_breakdown_sheet.dart',
    ];

    for (final path in listScreens) {
      final source = File(path).readAsStringSync();
      expect(source, contains('EmptyState('), reason: path);
    }
  });

  test('migrated list screens no longer define custom empty list widgets', () {
    final stationHistory = File(
      'lib/features/station/screens/station_consumption_history_screen.dart',
    ).readAsStringSync();

    expect(stationHistory, isNot(contains('class _EmptyHistoryCard')));
  });

  test('client carnet, QR, history and wallet lists share EmptyState', () {
    final carnets = File(
      'lib/features/home/screens/faces_detail_screen.dart',
    ).readAsStringSync();
    final qrs = File(
      'lib/features/qr/screens/qr_list_screen.dart',
    ).readAsStringSync();
    final transactions = File(
      'lib/features/transactions/screens/transactions_screen.dart',
    ).readAsStringSync();

    expect(carnets, contains(': allLines.isEmpty'));
    expect(carnets, contains('EmptyState('));
    expect(qrs, contains(': qrs.isEmpty'));
    expect(qrs, contains('EmptyState('));
    expect(qrs, isNot(contains('class _QrEmptyState')));
    expect(transactions, contains('child: txs.isEmpty'));
    expect(transactions, contains('EmptyState('));
    expect(transactions, contains('TransactionsScreenMode.wallet'));
    expect(transactions, contains('return l10n.transactionsHistoryTitle;'));
    expect(transactions, contains('return l10n.walletMovementsTitle;'));
  });

  test('EmptyState owns the shared size and positioning rules', () {
    final source = File(
      'lib/shared/widgets/empty_state.dart',
    ).readAsStringSync();

    expect(source, contains('static const double standardHeight = 360;'));
    expect(source, contains('static const double illustrationWidth = 190;'));
    expect(source, contains('alignment: Alignment.topCenter'));
    expect(source, contains('height: standardHeight'));
    expect(source, isNot(contains('child: Center(')));
  });
}
