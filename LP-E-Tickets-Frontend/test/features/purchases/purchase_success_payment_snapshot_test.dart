import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/core/utils/formatters.dart';
import 'package:fueltoken_app/domain/models/purchase/purchase_receipt.dart';
import 'package:fueltoken_app/features/purchases/screens/purchase_success_screen.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'purchase receipt shows the saved payment method and merchant code',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PurchaseSubmitSuccessScreen(
            result: const AcpecPurchaseCreateResult(
              purchaseId: '12',
              publicCode: 'PUB12',
              operationReference: 'TX-20261026-134604-0001',
              state: 'submitted',
              paymentMethodName: 'Bankily',
              paymentMerchantCode: '12345',
            ),
            confirmedAt: DateTime(2026, 10, 26),
          ),
        ),
      );

      expect(find.text('Moyen de paiement'), findsOneWidget);
      expect(find.text('Référence opération'), findsOneWidget);
      expect(find.text('TX-20261026-134604-0001'), findsOneWidget);
      expect(find.text('Bankily'), findsOneWidget);
      expect(find.text('Code commerçant'), findsOneWidget);
      expect(find.text('12345'), findsOneWidget);
      final dateText = Formatters.dateTimeDash(DateTime(2026, 10, 26));
      final dateWidget = tester.widget<Text>(find.text(dateText));
      expect(dateWidget.maxLines, 1);
      expect(dateWidget.softWrap, isFalse);
      expect(find.byType(Divider), findsNWidgets(4));
      for (final label in ['Moyen de paiement', 'Code commerçant']) {
        final labelWidget = tester.widget<Text>(find.text(label));
        expect(labelWidget.maxLines, 1, reason: label);
        expect(labelWidget.softWrap, isFalse, reason: label);
      }
    },
  );
}
