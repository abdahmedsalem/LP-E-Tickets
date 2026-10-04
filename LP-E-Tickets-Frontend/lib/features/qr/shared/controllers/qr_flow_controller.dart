import '../../../../core/controllers/flow_controller.dart';
import '../../../../domain/models/qr/qr_token.dart';
import '../../../../domain/repositories/qr_actions_repository.dart';

/// Shared QR detail, mapping and cache operations used by QR sub-flows.
class QrFlowController extends FlowController {
  QrFlowController({required this.repository});

  final QrActionsRepositoryContract repository;

  Future<QrToken> loadDetail(
    String routeId, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) => execute(
    'load',
    () => repository.loadDetail(
      routeId,
      ownerId: ownerId,
      ownerName: ownerName,
      companyId: companyId,
    ),
  );

  QrToken parseQr(
    dynamic raw, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) => repository.parseQr(
    raw,
    ownerId: ownerId,
    ownerName: ownerName,
    companyId: companyId,
  );

  void invalidateDetail(String routeId) => repository.invalidateDetail(routeId);

  void invalidateList() => repository.invalidateList();
}
