import '../../api/acpec_fueltoken_jsonrpc_api.dart';
import '../shared_services/acpec_rpc_result_guard.dart';

import '../../../domain/models/profile/account_deletion_receipt.dart';
import '../../../domain/models/profile/account_deletion_status.dart';
import 'account_deletion_receipt_mapper.dart';
import 'account_deletion_status_mapper.dart';
export '../../../domain/models/profile/account_deletion_receipt.dart';

class AccountDeletionService {
  AccountDeletionService({AcpecFueltokenJsonRpcApi? api})
    : _api = api ?? AcpecFueltokenJsonRpcApi();
  final AcpecFueltokenJsonRpcApi _api;
  static const statusRoute =
      '/api/acpec/mobile_auth/v1/account-deletion/status';
  static const requestRoute =
      '/api/acpec/mobile_auth/v1/account-deletion/request';

  Future<AccountDeletionStatus> status() async =>
      AccountDeletionStatusMapper.fromResponse(
        acpecRpcMapOrThrow(
          await _api.callRoute(statusRoute),
          fallbackMessage: 'Suppression de compte indisponible.',
        ),
      );

  Future<AccountDeletionReceipt> submit(String actionCode) async {
    final data = acpecRpcMapOrThrow(
      await _api.callRoute(
        requestRoute,
        params: {'action_code': actionCode, 'confirmed': true},
      ),
      fallbackMessage: 'Demande de suppression non confirmée.',
    );
    return AccountDeletionReceiptMapper.fromJson(data);
  }
}
