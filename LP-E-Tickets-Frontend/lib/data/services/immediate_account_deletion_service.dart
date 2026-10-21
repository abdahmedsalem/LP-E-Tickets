import 'package:uuid/uuid.dart';

import '../../core/auth/auth_token_store.dart';
import '../../core/auth/login_session_cache.dart';
import '../../core/auth/odoo_session_store.dart';
import '../../core/auth/secure_kv.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../api/acpec_fueltoken_jsonrpc_api.dart';
import 'shared_services/acpec_rpc_result_guard.dart';

class DeletionWalletReport {
  DeletionWalletReport.fromJson(Map<String, dynamic> json) : data = json {
    if (json['snapshot'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(json['snapshot'] as String) ||
        json['has_value'] is! bool ||
        json['retention_notice'] is! String ||
        (json['retention_notice'] as String).trim().isEmpty) {
      throw const FormatException('Invalid deletion report');
    }
    for (final key in ['wallets', 'carnets', 'qrs']) {
      if (json[key] is! List || (json[key] as List).any((row) => row is! Map)) {
        throw const FormatException('Invalid deletion report rows');
      }
    }
    if (json['blockers'] is! List ||
        (json['blockers'] as List).any((item) => item is! String)) {
      throw const FormatException('Invalid deletion blockers');
    }
  }

  final Map<String, dynamic> data;
  String get snapshot => data['snapshot'] as String;
  bool get hasValue => data['has_value'] as bool;
  bool get blocked => (data['blockers'] as List).isNotEmpty;
  String get retentionNotice => data['retention_notice'] as String;
  List<Map<String, dynamic>> rows(String key) => (data[key] as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
}

abstract class DeletionRecoveryStore {
  Future<String?> read();
  Future<void> write(String key);
  Future<void> clear();
}

class SecureDeletionRecoveryStore implements DeletionRecoveryStore {
  static const key = 'ft_deletion_recovery_key';
  @override
  Future<String?> read() => SecureKv.read(key);
  @override
  Future<void> write(String value) => SecureKv.write(key, value);
  @override
  Future<void> clear() => SecureKv.delete(key);
}

class ImmediateAccountDeletionService {
  ImmediateAccountDeletionService({
    AcpecFueltokenJsonRpcApi? api,
    DeletionRecoveryStore? recoveryStore,
  }) : _api = api ?? AcpecFueltokenJsonRpcApi(),
       _store = recoveryStore ?? SecureDeletionRecoveryStore();

  final AcpecFueltokenJsonRpcApi _api;
  final DeletionRecoveryStore _store;
  static const route = '/api/acpec/mobile_auth/v1/account-deletion';

  Future<DeletionWalletReport> preview() async => DeletionWalletReport.fromJson(
    acpecRpcMapOrThrow(
      await _api.callRoute('$route/preview'),
      fallbackMessage: 'Suppression temporairement indisponible.',
    ),
  );

  Future<bool> recover() async {
    final key = await _store.read();
    if (key == null) return false;
    final data = acpecRpcMapOrThrow(
      await _api.callRouteWithoutSession(
        '$route/recover',
        params: {'recovery_key': key},
      ),
      fallbackMessage: 'Impossible de vérifier la suppression.',
    );
    if (data['expired'] == true) await _store.clear();
    return _completed(data);
  }

  bool _completed(Map<String, dynamic> data) =>
      data['completed'] == true &&
      data['reference'] is String &&
      (data['reference'] as String).trim().isNotEmpty;

  Future<void> execute({
    required String pin,
    required DeletionWalletReport report,
    required bool waiveValue,
  }) async {
    if (report.blocked || (report.hasValue && !waiveValue)) {
      throw StateError('Wallet settlement requires explicit confirmation');
    }
    final key = await _store.read() ?? const Uuid().v4();
    await _store.write(key);
    // Never send a destructive request without a durable recovery credential.
    if (await _store.read() != key) {
      throw StateError('Unable to persist deletion receipt key');
    }
    try {
      final data = acpecRpcMapOrThrow(
        await _api.callRoute(
          '$route/execute',
          params: {
            'action_code': pin,
            'confirmed': true,
            'snapshot': report.snapshot,
            'waive_value': waiveValue,
            'recovery_key': key,
          },
        ),
        fallbackMessage: 'Suppression non confirmée.',
      );
      if (!_completed(data)) {
        throw const FormatException('Deletion unconfirmed');
      }
    } catch (_) {
      // A timeout can happen after Odoo committed and revoked the session.
      // Recover without authentication; never turn an uncertain result into success.
      try {
        if (await recover()) return;
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> clearLocalSession() async {
    await OdooSessionStore.clear();
    await AuthTokenStore.clear();
    await LoginSessionCache.clear();
    await LoginSessionCache.setBiometricPreferred(false);
    AcpecFueltokenRpcCoordinator.shared.clearCache();
  }

  Future<void> acknowledge() => _store.clear();
}
