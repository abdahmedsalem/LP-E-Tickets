import '../../../core/controllers/flow_controller.dart';
import '../../../domain/models/profile/account_deletion_receipt.dart';
import '../../../domain/models/profile/account_deletion_status.dart';
import '../../../domain/repositories/profile_repository.dart';

class ProfileController extends FlowController {
  ProfileController({required ProfileRepositoryContract repository})
    : _repository = repository;

  final ProfileRepositoryContract _repository;

  Future<AccountDeletionStatus> accountDeletionStatus() =>
      execute('accountDeletionStatus', _repository.accountDeletionStatus);

  Future<AccountDeletionReceipt> requestAccountDeletion(String actionCode) =>
      execute(
        'requestAccountDeletion',
        () => _repository.requestAccountDeletion(actionCode),
      );
}
