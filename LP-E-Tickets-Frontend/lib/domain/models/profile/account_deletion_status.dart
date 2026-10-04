import 'account_deletion_receipt.dart';

/// Account deletion policy and any request already opened for this account.
class AccountDeletionStatus {
  const AccountDeletionStatus({this.processingDays, this.existingRequest});

  final int? processingDays;
  final AccountDeletionReceipt? existingRequest;
}
