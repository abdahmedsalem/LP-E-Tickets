import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/models/business_transaction.dart';

void main() {
  BusinessTransaction transaction(TxType type, String? note) {
    return BusinessTransaction(
      id: 'tx-1',
      type: type,
      date: DateTime(2026, 7, 16),
      userId: 'user-1',
      userName: 'Client',
      lines: const [],
      note: note,
    );
  }

  test('pending purchase has no note before a decision', () {
    expect(
      transaction(
        TxType.purchaseSubmitted,
        'Commande de carnets',
      ).pendingPurchaseDecisionLabel,
      isNull,
    );
  });

  test('pending purchase note reports a validation decision', () {
    expect(
      transaction(
        TxType.purchaseSubmitted,
        'Carnets achetés',
      ).pendingPurchaseDecisionLabel,
      'Commande validée',
    );
  });

  test('pending purchase note reports a refusal decision', () {
    expect(
      transaction(
        TxType.purchaseSubmitted,
        'Commande de carnets rejetée',
      ).pendingPurchaseDecisionLabel,
      'Commande refusée',
    );
  });

  test('decided purchase cards never display the pending purchase note', () {
    expect(
      transaction(
        TxType.purchaseValidated,
        'Carnets achetés',
      ).pendingPurchaseDecisionLabel,
      isNull,
    );
    expect(
      transaction(
        TxType.purchaseRejected,
        'Commande de carnets rejetée',
      ).pendingPurchaseDecisionLabel,
      isNull,
    );
  });
}
