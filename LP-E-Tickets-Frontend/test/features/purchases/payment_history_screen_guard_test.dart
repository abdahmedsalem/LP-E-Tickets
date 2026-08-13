import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'payment history exposes proof actions and expandable purchase data',
    () {
      final source = File(
        'lib/features/purchases/screens/payment_history_screen.dart',
      ).readAsStringSync();

      expect(source, contains('facade.purchasesList'));
      expect(source, contains('facade.purchasesDetail'));
      expect(source, contains('AcpecPurchasesMapper.parsePurchaseDetail'));
      expect(source, contains('_loadMissingProofs'));
      expect(source, contains('ExpansionPanelList.radio'));
      expect(source, contains('purchase.internalRef'));
      expect(source, contains('purchase.publicCode'));
      expect(source, contains('purchase.paymentReference'));
      expect(source, contains('Formatters.money(purchase.totalAmount)'));
      expect(source, contains('Formatters.dateTime(purchaseDate)'));
      expect(source, contains('InteractiveViewer'));
      expect(source, contains('FilePicker.saveFile'));
      expect(source, contains('PaymentProofLoader.fetchBytes'));
      expect(source, contains('l10n.paymentHistoryProofUnavailable'));
      expect(source, isNot(contains('l10n.purchaseNoProof')));
    },
  );
}
