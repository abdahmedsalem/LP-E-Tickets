import '../models/profile/account_deletion_receipt.dart';
import '../models/profile/account_deletion_status.dart';

abstract interface class ProfileRepositoryContract {
  Future<AccountDeletionStatus> accountDeletionStatus();
  Future<AccountDeletionReceipt> requestAccountDeletion(String actionCode);
}
