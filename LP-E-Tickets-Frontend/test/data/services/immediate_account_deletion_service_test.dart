import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/api/acpec_fueltoken_jsonrpc_api.dart';
import 'package:fueltoken_app/data/services/immediate_account_deletion_service.dart';

class MemoryRecoveryStore implements DeletionRecoveryStore {
  String? value;
  bool writable = true;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String key) async {
    if (writable) value = key;
  }

  @override
  Future<void> clear() async => value = null;
}

class DeletionApi extends AcpecFueltokenJsonRpcApi {
  Map<String, dynamic>? sent;
  String? sentRoute;
  bool loseResponse = false;
  bool recoverCompleted = false;
  bool recoverExpired = false;
  Object response = {
    'ok': true,
    'data': {'completed': true, 'reference': 'DEL-test'},
  };
  @override
  Future<dynamic> callRoute(
    String route, {
    Map<String, dynamic>? params,
  }) async {
    sentRoute = route;
    sent = params;
    if (loseResponse) throw Exception('network timeout');
    return response;
  }

  @override
  Future<dynamic> callRouteWithoutSession(
    String route, {
    Map<String, dynamic>? params,
    Map<String, String>? extraHeaders,
  }) async => {
    'ok': true,
    'data': {
      'completed': recoverCompleted,
      if (recoverExpired) 'expired': true,
      if (recoverCompleted) 'reference': 'DEL-test',
    },
  };
}

Map<String, dynamic> reportData({
  bool value = false,
  List<String> blockers = const [],
}) => {
  'snapshot': List.filled(64, 'a').join(),
  'has_value': value,
  'blockers': blockers,
  'retention_notice': 'Test financial retention policy.',
  'wallets': [],
  'carnets': [],
  'qrs': [],
};

void main() {
  test(
    'sends PIN, snapshot and explicit waiver with durable recovery key',
    () async {
      final api = DeletionApi();
      final store = MemoryRecoveryStore();
      await ImmediateAccountDeletionService(
        api: api,
        recoveryStore: store,
      ).execute(
        pin: '1234',
        report: DeletionWalletReport.fromJson(reportData(value: true)),
        waiveValue: true,
      );
      expect(api.sentRoute, '${ImmediateAccountDeletionService.route}/execute');
      expect(api.sent, {
        'action_code': '1234',
        'confirmed': true,
        'snapshot': reportData()['snapshot'],
        'waive_value': true,
        'recovery_key': store.value,
      });
      expect(store.value, isNotNull);
      expect(api.sent!.containsKey('user_id'), isFalse);
    },
  );

  test(
    'does not submit without waiver or with unresolved operations',
    () async {
      for (final report in [
        reportData(value: true),
        reportData(blockers: ['station_operation']),
      ]) {
        final api = DeletionApi();
        await expectLater(
          ImmediateAccountDeletionService(
            api: api,
            recoveryStore: MemoryRecoveryStore(),
          ).execute(
            pin: '1234',
            report: DeletionWalletReport.fromJson(report),
            waiveValue: false,
          ),
          throwsStateError,
        );
        expect(api.sentRoute, isNull);
      }
    },
  );

  test('does not submit if secure recovery storage fails', () async {
    final api = DeletionApi();
    final store = MemoryRecoveryStore()..writable = false;
    await expectLater(
      ImmediateAccountDeletionService(api: api, recoveryStore: store).execute(
        pin: '1234',
        report: DeletionWalletReport.fromJson(reportData()),
        waiveValue: false,
      ),
      throwsStateError,
    );
    expect(api.sentRoute, isNull);
  });

  test(
    'recovers a committed deletion after response loss without session',
    () async {
      final api = DeletionApi()
        ..loseResponse = true
        ..recoverCompleted = true;
      final store = MemoryRecoveryStore();
      final service = ImmediateAccountDeletionService(
        api: api,
        recoveryStore: store,
      );
      await service.execute(
        pin: '1234',
        report: DeletionWalletReport.fromJson(reportData()),
        waiveValue: false,
      );
      expect(store.value, isNotNull);
      await service.acknowledge();
      expect(store.value, isNull);
    },
  );

  test(
    'never claims success for an unconfirmed timeout or malformed receipt',
    () async {
      for (final api in [
        DeletionApi()..loseResponse = true,
        DeletionApi()
          ..response = {
            'ok': true,
            'data': {'completed': true},
          },
      ]) {
        await expectLater(
          ImmediateAccountDeletionService(
            api: api,
            recoveryStore: MemoryRecoveryStore(),
          ).execute(
            pin: '1234',
            report: DeletionWalletReport.fromJson(reportData()),
            waiveValue: false,
          ),
          throwsA(isA<Exception>()),
        );
      }
    },
  );

  test('rejects malformed report instead of assuming an empty wallet', () {
    final data = reportData()..remove('has_value');
    expect(() => DeletionWalletReport.fromJson(data), throwsFormatException);
    expect(
      () => DeletionWalletReport.fromJson(reportData()..['qrs'] = null),
      throwsFormatException,
    );
  });

  test(
    'expired recovery key does not block a future account deletion',
    () async {
      final api = DeletionApi()..recoverExpired = true;
      final store = MemoryRecoveryStore()..value = 'expired-key';
      final service = ImmediateAccountDeletionService(
        api: api,
        recoveryStore: store,
      );
      expect(await service.recover(), isFalse);
      expect(store.value, isNull);
    },
  );
}
