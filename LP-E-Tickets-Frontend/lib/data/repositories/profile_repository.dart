import '../services/profile_services/account_deletion_service.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/models/profile/account_deletion_status.dart';

class ProfileRepository implements ProfileRepositoryContract {
  ProfileRepository({AccountDeletionService? deletionService})
    : _deletionService = deletionService ?? AccountDeletionService();

  final AccountDeletionService _deletionService;

  @override
  Future<AccountDeletionStatus> accountDeletionStatus() =>
      _deletionService.status();

  @override
  Future<AccountDeletionReceipt> requestAccountDeletion(String actionCode) =>
      _deletionService.submit(actionCode);
}
