import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/api/acpec_fueltoken_jsonrpc_api.dart';
import 'package:fueltoken_app/data/services/profile_services/account_deletion_service.dart';

class FakeApi extends AcpecFueltokenJsonRpcApi {
  FakeApi(this.response);
  dynamic response;
  String? route;
  Map<String, dynamic>? params;
  @override
  Future<dynamic> callRoute(
    String route, {
    Map<String, dynamic>? params,
  }) async {
    this.route = route;
    this.params = params;
    return response;
  }
}

void main() {
  final receipt = {
    'reference': 'DEL-123',
    'state': 'pending',
    'due_at': '2026-10-01T12:00:00Z',
  };
  test('request sends confirmation and PIN, never a target user', () async {
    final api = FakeApi({'ok': true, 'data': receipt});
    final result = await AccountDeletionService(api: api).submit('1234');
    expect(api.route, '/api/acpec/mobile_auth/v1/account-deletion/request');
    expect(api.params, {'confirmed': true, 'action_code': '1234'});
    expect(result.reference, 'DEL-123');
    expect(result.state, 'pending');
    expect(result.dueAt.isUtc, isTrue);
  });
  test('empty or incomplete responses never confirm submission', () async {
    for (final data in [
      {},
      {'ok': true},
      {'ok': true, 'data': {}},
      {
        'ok': true,
        'data': {...receipt, 'state': 'unknown'},
      },
      {
        'ok': true,
        'data': {...receipt, 'due_at': 'invalid'},
      },
    ]) {
      await expectLater(
        AccountDeletionService(api: FakeApi(data)).submit('1234'),
        throwsA(isA<FormatException>()),
      );
    }
  });
  test('business refusal is not a receipt even with receipt fields', () async {
    await expectLater(
      AccountDeletionService(
        api: FakeApi({'ok': false, 'data': receipt}),
      ).submit('1234'),
      throwsException,
    );
  });
  test('status retrieves an existing request after a lost response', () async {
    final api = FakeApi({
      'ok': true,
      'data': {'request': receipt, 'processing_days': 14},
    });
    final status = await AccountDeletionService(api: api).status();
    expect(api.route, '/api/acpec/mobile_auth/v1/account-deletion/status');
    expect(status.existingRequest?.reference, 'DEL-123');
    expect(status.processingDays, 14);
    expect(api.params, isNull);
  });
}
