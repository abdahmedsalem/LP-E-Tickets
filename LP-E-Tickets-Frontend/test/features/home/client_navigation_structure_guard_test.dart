import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('client bottom navigation exposes the four requested tabs in order', () {
    final source = File(
      'lib/features/home/screens/client_shell_scaffold.dart',
    ).readAsStringSync();

    expect(
      RegExp(
        r'label: l10n\.nav(?:Home|Wallet|History|Portfolio)',
      ).allMatches(source),
      hasLength(4),
    );

    final home = source.indexOf('label: l10n.navHome');
    final operations = source.indexOf('label: l10n.navWallet');
    final history = source.indexOf('label: l10n.navHistory');
    final portfolio = source.indexOf('label: l10n.navPortfolio');

    expect(home, greaterThanOrEqualTo(0));
    expect(operations, greaterThan(home));
    expect(history, greaterThan(operations));
    expect(portfolio, greaterThan(history));
    expect(source, isNot(contains('label: l10n.navCarnets')));
    expect(source, isNot(contains('label: l10n.navQr')));
  });

  test('portfolio groups carnet and QR entry points in one shell branch', () {
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    final portfolio = File(
      'lib/features/home/screens/client_portfolio_screen.dart',
    ).readAsStringSync();

    final home = router.indexOf("path: '/home'");
    final operations = router.indexOf("path: '/wallet'");
    final history = router.indexOf("path: '/transactions'");
    final portfolioBranch = router.indexOf("path: '/portfolio'");

    expect(operations, greaterThan(home));
    expect(history, greaterThan(operations));
    expect(portfolioBranch, greaterThan(history));
    expect(router, contains("path: 'faces'"));
    expect(router, contains("path: 'qr'"));
    expect(router, contains("'/portfolio/faces'"));
    expect(router, contains("'/portfolio/qr'"));
    expect(portfolio, contains("context.go('/portfolio/faces')"));
    expect(portfolio, contains("context.go('/portfolio/qr')"));
  });

  test('portfolio bottom tab opens a popup menu for carnets and QR', () {
    final shell = File(
      'lib/features/home/screens/client_shell_scaffold.dart',
    ).readAsStringSync();

    expect(shell, contains('PopupMenuButton<_PortfolioDestination>'));
    expect(shell, contains('value: _PortfolioDestination.carnets'));
    expect(shell, contains('value: _PortfolioDestination.qr'));
    expect(shell, contains('label: l10n.carnetsTitle'));
    expect(shell, contains('label: l10n.qrsTitle'));
    expect(shell, contains("context.go('/portfolio/faces')"));
    expect(shell, contains("context.go('/portfolio/qr')"));
  });
}
