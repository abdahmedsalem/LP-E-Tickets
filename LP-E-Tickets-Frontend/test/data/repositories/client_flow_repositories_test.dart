import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/repositories/purchase_repository.dart';
import 'package:fueltoken_app/data/repositories/transfer_repository.dart';
import 'package:fueltoken_app/data/repositories/qr_generation_repository.dart';
import 'package:fueltoken_app/data/services/shared_services/odoo_fueltoken_facade.dart';

class FakeApi implements OdooFueltokenFacade {
  dynamic response;
  final calls = <String>[];
  Map<String, dynamic>? payload;
  Future<dynamic> record(String name, Map<String, dynamic> params) async {
    calls.add(name);
    payload = params;
    return response;
  }

  @override
  Future<dynamic> purchasesCreate(Map<String, dynamic> p) =>
      record('purchase', p);
  @override
  Future<dynamic> carnetsTransfer(Map<String, dynamic> p) =>
      record('carnets', p);
  @override
  Future<dynamic> ticketsTransfer(Map<String, dynamic> p) =>
      record('tickets', p);
  @override
  Future<dynamic> qrIssue(Map<String, dynamic> p) => record('qr', p);
  @override
  Future<dynamic> carnetsTransferRecipient(Map<String, dynamic> p) =>
      record('recipient', p);
  @override
  Future<dynamic> faces([Map<String, dynamic>? p]) async {
    calls.add('faces');
    payload = p;
    throw StateError('offline');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'recipient lookup distinguishes a server refusal from an absent name',
    () async {
      final api = FakeApi()
        ..response = {
          'ok': true,
          'data': {'recipient_name': ' Client '},
        };
      final repository = TransferRepository(api: api);
      expect(await repository.recipientName('22000000'), 'Client');
      expect(api.payload, {'recipient_phone': '22000000'});
      api.response = {'ok': true, 'data': {}};
      expect(await repository.recipientName('22000000'), isNull);
      api.response = {
        'ok': false,
        'error': {'code': 'AUTH_REFUSED'},
      };
      await expectLater(repository.recipientName('22000000'), throwsException);
      api.response = null;
      await expectLater(repository.recipientName('22000000'), throwsException);
    },
  );
  test('four flow screens do not depend on API access services', () {
    for (final path in [
      'lib/features/purchases/screens/submit_purchase_screen.dart',
      'lib/features/qr/generation/screens/emit_qr_screen.dart',
      'lib/features/transfer/screens/transfer_carnets_screen.dart',
      'lib/features/transfer/screens/transfer_tickets_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final forbidden in [
        'OdooFueltokenFacade',
        'AcpecCarnetCatalogService',
        'AcpecPaymentMethodsService',
        'AcpecFueltokenRpcCoordinator',
        'OdooJsonRpcClient(',
        'callRoute(',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: '$path: $forbidden');
      }
      expect(source, contains('_controller.'));
      expect(source, isNot(contains('data/repositories/')));
    }
  });
  for (final carnets in [true, false]) {
    test('transfer inventory keeps its original filter: $carnets', () async {
      final api = FakeApi();
      await expectLater(
        TransferRepository(api: api).loadTransferInventory(
          ownerId: '1',
          companyId: '1',
          transferableOnly: carnets,
        ),
        throwsStateError,
      );
      expect(api.payload, carnets ? {'transferable_only': true} : {});
      expect(api.calls, ['faces']);
    });
  }
  const payload = <String, dynamic>{
    'action_code': '1234',
    'idempotency_key': 'stable-intent',
    'lines': [
      {'line_id': 12, 'qty': 1},
    ],
  };
  test('purchase preserves request and parses the receipt', () async {
    final api = FakeApi()
      ..response = {
        'ok': true,
        'data': {'purchase_id': 9, 'public_code': 'P9', 'state': 'submitted'},
      };
    final result = await PurchaseRepository(api: api).purchasesCreate(payload);
    expect(result.purchaseId, '9');
    expect(result.publicCode, 'P9');
    expect(api.payload, payload);
    expect(api.calls, ['purchase']);
  });
  for (final tickets in [false, true]) {
    test(
      'transfer ${tickets ? 'tickets' : 'carnets'} preserves intent and rejects refusal',
      () async {
        final api = FakeApi()
          ..response = {
            'ok': true,
            'data': {'dest_partner': 'Client'},
          };
        final repo = TransferRepository(api: api);
        Future<Map<String, dynamic>> send() => tickets
            ? repo.ticketsTransfer(
                payload,
                fallbackMessage: 'Refus',
                publicErrorMessage: 'Échec',
              )
            : repo.carnetsTransfer(
                payload,
                fallbackMessage: 'Refus',
                publicErrorMessage: 'Échec',
              );
        expect((await send())['dest_partner'], 'Client');
        expect(api.payload, payload);
        expect(api.calls, [tickets ? 'tickets' : 'carnets']);
        api.response = {
          'ok': false,
          'error': {'code': 'TRANSFER_REFUSED', 'message': 'Refus'},
        };
        await expectLater(send(), throwsException);
      },
    );
  }
  test(
    'QR refuses failed issuance without retrying or losing the intent',
    () async {
      final api = FakeApi()
        ..response = {
          'ok': false,
          'error': {'code': 'INVALID_ACTION_CODE', 'message': 'Refus'},
        };
      await expectLater(
        QrGenerationRepository(api: api).qrIssue(
          payload,
          ownerId: '1',
          ownerName: 'Client',
          companyId: '1',
          publicErrorMessage: 'Échec',
        ),
        throwsException,
      );
      expect(api.payload, payload);
      expect(api.calls, ['qr']);
    },
  );
}
