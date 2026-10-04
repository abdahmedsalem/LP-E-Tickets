import 'carnet_flow_repository.dart';
import '../../domain/repositories/qr_generation_repository.dart';
import '../../domain/models/qr/qr_issue_receipt.dart';
import '../../domain/models/qr/qr_limit_settings.dart';
import '../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../services/shared_services/acpec_rpc_result_guard.dart';
import '../services/qr_services/acpec_qr_mapper.dart';

class QrGenerationRepository extends CarnetFlowRepository
    implements QrGenerationRepositoryContract {
  QrGenerationRepository({super.api});
  @override
  Future<QrLimitSettings> qrLimitSettings() async {
    final response = acpecRpcMapOrThrow(
      await api.walletCurrent(const <String, dynamic>{}),
      fallbackMessage: 'Impossible de charger le plafond QR enregistré.',
    );
    return _readQrSettings(response);
  }

  @override
  Future<int> walletQrLimit(int maxAmount) async {
    final savedResponse = acpecRpcMapOrThrow(
      await api.walletQrLimit({'max_amount': maxAmount}),
      fallbackMessage:
          'Le serveur n’a pas confirmé l’enregistrement du plafond QR.',
    );
    final savedAmount = _readQrSettings(savedResponse).maxAmount;
    if (savedAmount != maxAmount) {
      throw StateError(
        'Le serveur n’a pas confirmé le plafond QR demandé. '
        'Valeur demandée : $maxAmount ; valeur retournée : ${savedAmount ?? 'absente'}.',
      );
    }

    // wallet/current est mis en cache pour les lectures. Vider l’entrée avant
    // une relecture permet de confirmer la valeur persistée côté Odoo.
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.walletCurrent,
      const <String, dynamic>{},
    );
    final walletResponse = acpecRpcMapOrThrow(
      await api.walletCurrent(const <String, dynamic>{}),
      fallbackMessage: 'Impossible de vérifier le plafond QR enregistré.',
    );
    final persistedAmount = _readQrSettings(walletResponse).maxAmount;
    if (persistedAmount != maxAmount) {
      throw StateError(
        'La relecture du portefeuille ne confirme pas le plafond QR demandé. '
        'Valeur demandée : $maxAmount ; valeur enregistrée : ${persistedAmount ?? 'absente'}.',
      );
    }
    // The equality check above proves this is non-null and equal to the
    // requested amount, but Dart cannot promote a value returned by a helper.
    return maxAmount;
  }

  QrLimitSettings _readQrSettings(Map<String, dynamic> response) {
    dynamic current = response;
    for (var depth = 0; depth < 5; depth++) {
      if (current is! Map) break;
      if (current.containsKey('qr_max_amount')) {
        final value = current['qr_max_amount'];
        final text = value?.toString().trim() ?? '';
        final amount = value is num
            ? value.round()
            : int.tryParse(text) ?? double.tryParse(text)?.round();
        final currency = current['currency']?.toString().trim();
        return QrLimitSettings(
          maxAmount: amount,
          currency: currency == null || currency.isEmpty ? null : currency,
        );
      }
      current = current['data'] ?? current['result'];
    }
    return const QrLimitSettings(maxAmount: null);
  }

  @override
  Future<QrIssueReceipt> qrIssue(
    Map<String, dynamic> params, {
    required String ownerId,
    required String ownerName,
    required String companyId,
    required String publicErrorMessage,
  }) async {
    final data = acpecRpcMapOrThrow(
      await api.qrIssue(params),
      fallbackMessage: 'Génération de QR refusée par le serveur.',
      publicErrorMessage: publicErrorMessage,
    );
    AcpecQrMapper.fromRpcIssueEnvelope(
      data,
      ownerId: ownerId,
      ownerName: ownerName,
      companyId: companyId,
    );
    final reference = data['transaction_reference']?.toString().trim();
    final name = data['name']?.toString().trim();
    return QrIssueReceipt(
      transactionReference: reference != null && reference.isNotEmpty
          ? reference
          : (name == null || name.isEmpty ? null : name),
    );
  }

  @override
  void invalidateAfterIssue() {
    AcpecFueltokenRpcCoordinator.shared.invalidateRoute(
      OdooFueltokenRpcConfig.qrList,
    );

    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.faces,
      null,
    );
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.transactions,
      null,
    );
  }
}
