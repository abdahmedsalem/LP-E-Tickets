import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/features/qr/generation/widgets/qr_limit_dialog.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';

void main() {
  Future<void> openDialog(
    WidgetTester tester,
    ValueChanged<int?> onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(
                await showDialog<int>(
                  context: context,
                  builder: (_) =>
                      const QrLimitDialog(currentAmount: 5000, currency: 'MRU'),
                ),
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('refuses invalid amounts without closing', (
    tester,
  ) async {
    var submitted = false;
    await openDialog(tester, (_) => submitted = true);
    for (final amount in ['0', '-1', '', '1.5']) {
      await tester.enterText(find.byType(TextFormField), amount);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(find.byType(QrLimitDialog), findsOneWidget);
      expect(submitted, isFalse);
      expect(
        find.text(
          'Saisissez un montant entier strictement positif.',
        ),
        findsOneWidget,
      );
    }
  });

  for (final input in ['1', '4999', '5 000', '5\u00a0000', '5001', '10000', '1000000']) {
    testWidgets('accepts $input and returns the selected amount', (
      tester,
    ) async {
      int? result;
      await openDialog(tester, (value) => result = value);
      await tester.enterText(find.byType(TextFormField), input);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(result, int.parse(input.replaceAll(RegExp(r'\s'), '')));
      expect(find.byType(QrLimitDialog), findsNothing);
    });
  }
}
