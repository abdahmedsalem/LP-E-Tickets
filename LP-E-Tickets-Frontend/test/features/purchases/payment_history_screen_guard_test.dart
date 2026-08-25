import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'payment history displays proof image inline without explanation panel',
    () {
      final source = File(
        'lib/features/purchases/screens/payment_history_screen.dart',
      ).readAsStringSync();

      expect(source, contains('facade.purchasesList'));
      expect(source, contains("'include_proof_data': true"));
      expect(source, contains('facade.purchasesDetail'));
      expect(source, contains('AcpecPurchasesMapper.parsePurchaseDetail'));
      expect(source, contains('_loadMissingProofs'));
      expect(source, isNot(contains('ExpansionPanelList.radio')));
      expect(source, isNot(contains('_PurchaseDetails')));
      expect(source, isNot(contains('purchase.internalRef')));
      expect(source, isNot(contains('purchase.publicCode')));
      expect(source, isNot(contains('purchase.paymentReference')));
      expect(source, contains('Formatters.money(purchase.totalAmount)'));
      expect(source, contains('Formatters.dateTime(purchaseDate)'));
      expect(source, contains('Image.memory'));
      expect(source, contains('Image.network'));
      expect(source, contains('BoxFit.contain'));
      expect(source, contains('InteractiveViewer'));
      expect(source, contains('FilePicker.saveFile'));
      expect(source, contains('PaymentProofLoader.fetchBytes'));
      expect(source, contains('l10n.paymentHistoryProofUnavailable'));
      expect(source, isNot(contains('l10n.purchaseNoProof')));
    },
  );
}
