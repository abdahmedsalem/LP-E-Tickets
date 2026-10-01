import '../api/acpec_fueltoken_jsonrpc_api.dart';
import 'acpec_rpc_result_guard.dart';

/// A receipt confirms a request, never that personal data has been erased.
class AccountDeletionReceipt {
  const AccountDeletionReceipt(this.reference, this.state, this.dueAt);
  final String reference;
  final String state;
  final DateTime dueAt;

  factory AccountDeletionReceipt.fromJson(Map<String, dynamic> data) {
    final reference = data['reference'];
    final state = data['state'];
    final dueAt = DateTime.tryParse(data['due_at']?.toString() ?? '');
    if (reference is! String ||
        reference.trim().isEmpty ||
        !const ['pending', 'in_progress', 'completed'].contains(state) ||
        dueAt == null) {
      throw const FormatException('Invalid deletion request receipt');
    }
    return AccountDeletionReceipt(reference, state as String, dueAt);
  }
}

class AccountDeletionService {
  AccountDeletionService({AcpecFueltokenJsonRpcApi? api})
    : _api = api ?? AcpecFueltokenJsonRpcApi();
  final AcpecFueltokenJsonRpcApi _api;
  static const route = '/api/acpec/mobile_auth/v1/account-deletion';

  Future<Map<String, dynamic>> status() async => acpecRpcMapOrThrow(
    await _api.callRoute('$route/status'),
    fallbackMessage: 'Suppression de compte indisponible.',
  );

  Future<AccountDeletionReceipt> submit(String actionCode) async {
    final data = acpecRpcMapOrThrow(
      await _api.callRoute(
        '$route/request',
        params: {'action_code': actionCode, 'confirmed': true},
      ),
      fallbackMessage: 'Demande de suppression non confirmée.',
    );
    return AccountDeletionReceipt.fromJson(data);
  }
}
