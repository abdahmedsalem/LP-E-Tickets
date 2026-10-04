import '../../../domain/models/profile/account_deletion_status.dart';
import 'account_deletion_receipt_mapper.dart';

class AccountDeletionStatusMapper {
  const AccountDeletionStatusMapper._();

  static AccountDeletionStatus fromResponse(Map<String, dynamic> data) {
    final rawDays = data['processing_days'];
    final days = rawDays is num
        ? rawDays.round()
        : int.tryParse(rawDays?.toString().trim() ?? '');

    final rawRequest = data['request'];
    final request = rawRequest is Map
        ? AccountDeletionReceiptMapper.fromJson(
            Map<String, dynamic>.from(rawRequest),
          )
        : null;
    if (request == null && (days == null || days < 1)) {
      throw const FormatException('Invalid deletion processing policy');
    }
    return AccountDeletionStatus(
      processingDays: days,
      existingRequest: request,
    );
  }
}
