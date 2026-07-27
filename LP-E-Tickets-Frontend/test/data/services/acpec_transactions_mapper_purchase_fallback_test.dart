import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/models/business_transaction.dart';
import 'package:fueltoken_app/data/models/purchase_lot.dart';
import 'package:fueltoken_app/data/services/acpec_transactions_mapper.dart';

void main() {
  group('AcpecTransactionsMapper.fromSubmittedPurchases', () {
    test('keeps only really submitted purchases as fallback history', () {
      final now = DateTime(2026, 7, 5, 12);
      final submitted = _lot(
        id: '101',
        state: PurchaseLotState.submitted,
        createdAt: now,
      );
      final approved = _lot(
        id: '102',
        state: PurchaseLotState.approved,
        createdAt: now.add(const Duration(minutes: 1)),
      );
      final rejected = _lot(
        id: '103',
        state: PurchaseLotState.rejected,
        createdAt: now.add(const Duration(minutes: 2)),
      );
      final draft = _lot(
        id: '104',
        state: PurchaseLotState.draft,
        createdAt: now.add(const Duration(minutes: 3)),
      );

      final txs = AcpecTransactionsMapper.fromSubmittedPurchases(
        [submitted, approved, rejected, draft],
        userId: 'client-1',
        userName: 'Client Test',
      );

      expect(txs, hasLength(1));
      expect(txs.single.type, TxType.purchaseSubmitted);
      expect(txs.single.lotId, '101');
      expect(txs.single.note, PurchaseLotState.submitted.label);
    });

    test('does not downgrade approved or rejected purchases to submitted', () {
      final now = DateTime(2026, 7, 5, 13);

      final txs = AcpecTransactionsMapper.fromSubmittedPurchases(
        [
          _lot(id: '201', state: PurchaseLotState.approved, createdAt: now),
          _lot(id: '202', state: PurchaseLotState.rejected, createdAt: now),
        ],
        userId: 'client-1',
        userName: 'Client Test',
      );

      expect(txs, isEmpty);
    });
  });
}

PurchaseLot _lot({
  required String id,
  required PurchaseLotState state,
  required DateTime createdAt,
}) {
  return PurchaseLot(
    id: id,
    internalRef: 'ACH/2026/$id',
    publicCode: 'PUR-$id',
    clientId: 'client-1',
    clientName: 'Client Test',
    companyId: '1',
    lines: [
      PurchaseLine(
        id: 'line-$id',
        carnetTypeId: 'ct-1',
        carnetTypeCode: 'C10-1000',
        carnetTypeName: 'Carnet 10 x 1000',
        carnetCount: 1,
        carnetSize: 10,
        faceValue: 1000,
      ),
    ],
    state: state,
    submittedAt: state == PurchaseLotState.submitted ? createdAt : null,
    approvedAt: state == PurchaseLotState.approved ? createdAt : null,
    rejectedAt: state == PurchaseLotState.rejected ? createdAt : null,
    createdAt: createdAt,
    expirationDate: createdAt.add(const Duration(days: 365)),
  );
}
