import '../../../../core/controllers/flow_controller.dart';
import '../../../../domain/repositories/qr_generation_repository.dart';
import '../../../../domain/models/purchase/carnet_flow_data.dart';
import '../../../../domain/models/qr/qr_issue_receipt.dart';
import '../../../../domain/models/qr/qr_limit_settings.dart';

class QrGenerationController extends FlowController {
  QrGenerationController({required QrGenerationRepositoryContract repository})
    : _repository = repository;
  final QrGenerationRepositoryContract _repository;
  Future<CarnetFlowData> loadFaces({
    required String ownerId,
    required String companyId,
  }) => execute(
    'inventory',
    () => _repository.loadFaces(ownerId: ownerId, companyId: companyId),
  );
  Future<QrLimitSettings> qrLimitSettings() =>
      execute('limitLoad', _repository.qrLimitSettings);
  Future<int> walletQrLimit(int maxAmount) =>
      execute('limitSave', () => _repository.walletQrLimit(maxAmount));
  Future<QrIssueReceipt> qrIssue(
    Map<String, dynamic> params, {
    required String ownerId,
    required String ownerName,
    required String companyId,
    required String publicErrorMessage,
  }) => execute('submit', () async {
    final result = await _repository.qrIssue(
      params,
      ownerId: ownerId,
      ownerName: ownerName,
      companyId: companyId,
      publicErrorMessage: publicErrorMessage,
    );
    _repository.invalidateAfterIssue();
    return result;
  });
}
