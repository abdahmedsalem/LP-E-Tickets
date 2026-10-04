import '../../../core/controllers/flow_controller.dart';
import '../../../domain/repositories/transfer_repository.dart';
import '../../../domain/models/transfer_inventory.dart';

class TransferCarnetsController extends FlowController {
  TransferCarnetsController({required TransferRepositoryContract repository})
    : _repository = repository;

  final TransferRepositoryContract _repository;

  Future<TransferInventoryCatalog> loadFaces({
    required String ownerId,
    required String companyId,
  }) => execute(
    'inventory',
    () => _repository.loadTransferInventory(
      ownerId: ownerId,
      companyId: companyId,
      transferableOnly: true,
    ),
  );

  Future<String?> recipientName(String phone) =>
      execute('recipient', () => _repository.recipientName(phone));

  Future<Map<String, dynamic>> carnetsTransfer(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  }) => execute(
    'submit',
    () => _repository.carnetsTransfer(
      params,
      fallbackMessage: fallbackMessage,
      publicErrorMessage: publicErrorMessage,
    ),
  );
}
