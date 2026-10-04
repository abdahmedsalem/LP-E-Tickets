import '../../../domain/models/profile/account_deletion_receipt.dart';

class AccountDeletionReceiptMapper {
  static AccountDeletionReceipt fromJson(Map<String, dynamic> data) {
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
