import '../../domain/models/transfer_inventory.dart';
import '../../domain/repositories/transfer_repository.dart';
import '../services/shared_services/odoo_fueltoken_facade.dart';
import '../services/transfer_inventory_mapper.dart';
import 'carnet_flow_repository.dart';
import '../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../services/shared_services/acpec_rpc_result_guard.dart';

class TransferRepository implements TransferRepositoryContract {
  TransferRepository({
    OdooFueltokenFacade? api,
    CarnetFlowRepository? inventoryRepository,
  }) : _api = api ?? OdooFueltokenFacade(),
       _inventoryRepository =
           inventoryRepository ?? CarnetFlowRepository(api: api);

  final OdooFueltokenFacade _api;
  final CarnetFlowRepository _inventoryRepository;

  @override
  Future<TransferInventoryCatalog> loadTransferInventory({
    required String ownerId,
    required String companyId,
    required bool transferableOnly,
  }) async {
    final data = await _inventoryRepository.loadFaces(
      ownerId: ownerId,
      companyId: companyId,
      transferableOnly: transferableOnly,
      mobileCatalog: true,
    );
    return TransferInventoryMapper.fromData(
      types: data.types,
      faces: data.faces,
    );
  }

  @override
  Future<String?> recipientName(String phone) async {
    final data = acpecRpcMapOrThrow(
      await _api.carnetsTransferRecipient({'recipient_phone': phone}),
      fallbackMessage: 'Recherche du destinataire indisponible.',
    );
    final name = data['recipient_name']?.toString().trim();
    return name == null || name.isEmpty ? null : name;
  }

  @override
  Future<Map<String, dynamic>> carnetsTransfer(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  }) async {
    final result = acpecRpcMapOrThrow(
      await _api.carnetsTransfer(params),
      fallbackMessage: fallbackMessage,
      publicErrorMessage: publicErrorMessage,
    );
    _invalidateTransferReadModels();
    return result;
  }

  @override
  Future<Map<String, dynamic>> ticketsTransfer(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  }) async {
    final result = acpecRpcMapOrThrow(
      await _api.ticketsTransfer(params),
      fallbackMessage: fallbackMessage,
      publicErrorMessage: publicErrorMessage,
    );
    _invalidateTransferReadModels();
    return result;
  }

  void _invalidateTransferReadModels() {
    final coordinator = AcpecFueltokenRpcCoordinator.shared;
    coordinator.invalidateRoute(OdooFueltokenRpcConfig.walletCurrent);
    coordinator.invalidateRoute(OdooFueltokenRpcConfig.faces);
    coordinator.invalidateRoute(OdooFueltokenRpcConfig.transactions);
  }
}
