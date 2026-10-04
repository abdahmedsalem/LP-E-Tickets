import '../models/purchase/carnet_flow_data.dart';
import '../models/qr/qr_issue_receipt.dart';
import '../models/qr/qr_limit_settings.dart';

abstract interface class QrGenerationRepositoryContract {
  Future<CarnetFlowData> loadFaces({
    required String ownerId,
    required String companyId,
  });
  Future<QrLimitSettings> qrLimitSettings();
  Future<int> walletQrLimit(int maxAmount);
  Future<QrIssueReceipt> qrIssue(
    Map<String, dynamic> params, {
    required String ownerId,
    required String ownerName,
    required String companyId,
    required String publicErrorMessage,
  });
  void invalidateAfterIssue();
}
