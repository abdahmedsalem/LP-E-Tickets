import '../models/transfer_inventory.dart';

abstract interface class TransferRepositoryContract {
  Future<TransferInventoryCatalog> loadTransferInventory({
    required String ownerId,
    required String companyId,
    required bool transferableOnly,
  });

  Future<String?> recipientName(String phone);

  Future<Map<String, dynamic>> carnetsTransfer(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  });

  Future<Map<String, dynamic>> ticketsTransfer(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  });
}
