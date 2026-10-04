import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/domain/repositories/purchase_repository.dart';
import 'package:fueltoken_app/domain/repositories/transfer_repository.dart';
import 'package:fueltoken_app/domain/repositories/qr_generation_repository.dart';
import 'package:fueltoken_app/domain/models/purchase/purchase_receipt.dart';
import 'package:fueltoken_app/domain/models/qr/qr_issue_receipt.dart';
import 'package:fueltoken_app/domain/models/transfer_inventory.dart';
import 'package:fueltoken_app/features/purchases/controllers/purchase_controller.dart';
import 'package:fueltoken_app/features/qr/generation/controllers/qr_generation_controller.dart';
import 'package:fueltoken_app/features/transfer/controllers/transfer_carnets_controller.dart';
import 'package:fueltoken_app/features/transfer/controllers/transfer_tickets_controller.dart';

class PurchaseFake implements PurchaseRepositoryContract {
  int calls = 0;
  final result = Completer<AcpecPurchaseCreateResult>();
  @override
  Future<AcpecPurchaseCreateResult> purchasesCreate(Map<String, dynamic> p) {
    calls++;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class TransferFake implements TransferRepositoryContract {
  bool? filter;
  @override
  Future<TransferInventoryCatalog> loadTransferInventory({
    required String ownerId,
    required String companyId,
    required bool transferableOnly,
  }) async {
    filter = transferableOnly;
    return const TransferInventoryCatalog(types: [], faces: []);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class QrFake implements QrGenerationRepositoryContract {
  final result = Completer<QrIssueReceipt>();
  int invalidations = 0;
  @override
  Future<QrIssueReceipt> qrIssue(
    Map<String, dynamic> p, {
    required String ownerId,
    required String ownerName,
    required String companyId,
    required String publicErrorMessage,
  }) => result.future;
  @override
  void invalidateAfterIssue() {
    invalidations++;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test(
    'purchase blocks duplicate submission and publishes completion state',
    () async {
      final repo = PurchaseFake();
      final controller = PurchaseController(repository: repo);
      final states = <bool>[];
      controller.addListener(() => states.add(controller.isRunning('submit')));
      final pending = controller.purchasesCreate({});
      expect(controller.isRunning('submit'), true);
      await expectLater(controller.purchasesCreate({}), throwsStateError);
      expect(repo.calls, 1);
      repo.result.complete(
        const AcpecPurchaseCreateResult(
          purchaseId: '1',
          publicCode: 'P1',
          state: 'submitted',
        ),
      );
      expect((await pending).purchaseId, '1');
      expect(states, [true, false]);
      controller.dispose();
    },
  );
  test('failure clears busy state, retains error and propagates it', () async {
    final repo = PurchaseFake();
    final controller = PurchaseController(repository: repo);
    final pending = controller.purchasesCreate({});
    final error = StateError('offline');
    final assertion = expectLater(pending, throwsA(same(error)));
    repo.result.completeError(error);
    await assertion;
    expect(controller.isRunning('submit'), false);
    expect(controller.errorFor('submit'), same(error));
    controller.dispose();
  });
  test(
    'dispose during request prevents later listener notifications',
    () async {
      final repo = PurchaseFake();
      final controller = PurchaseController(repository: repo);
      final pending = controller.purchasesCreate({});
      controller.dispose();
      repo.result.complete(
        const AcpecPurchaseCreateResult(
          purchaseId: '1',
          publicCode: 'P1',
          state: 'submitted',
        ),
      );
      await pending;
      await expectLater(controller.purchasesCreate({}), throwsStateError);
    },
  );
  test('transfer controllers own distinct inventory rules', () async {
    final repo = TransferFake();
    final carnets = TransferCarnetsController(repository: repo);
    final tickets = TransferTicketsController(repository: repo);
    await carnets.loadFaces(ownerId: '1', companyId: '1');
    expect(repo.filter, true);
    await tickets.loadFaces(ownerId: '1', companyId: '1');
    expect(repo.filter, false);
    carnets.dispose();
    tickets.dispose();
  });
  for (final success in [true, false]) {
    test('QR invalidates cache only after success: $success', () async {
      final repo = QrFake();
      final controller = QrGenerationController(repository: repo);
      final pending = controller.qrIssue(
        {},
        ownerId: '1',
        ownerName: 'Client',
        companyId: '1',
        publicErrorMessage: 'Échec',
      );
      expect(repo.invalidations, 0);
      if (success) {
        repo.result.complete(const QrIssueReceipt(transactionReference: 'QR1'));
        await pending;
      } else {
        final check = expectLater(pending, throwsStateError);
        repo.result.completeError(StateError('refused'));
        await check;
      }
      expect(repo.invalidations, success ? 1 : 0);
      expect(controller.isRunning('submit'), false);
      controller.dispose();
    });
  }
}
