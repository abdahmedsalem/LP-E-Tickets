import '../../../core/controllers/flow_controller.dart';
import '../../../domain/models/history/acpec_transactions_page.dart';
import '../../../domain/models/station/station_profile.dart';
import '../../../domain/models/station/station_consumption_receipt.dart';
import '../../../domain/models/station/station_location.dart';
import '../../../domain/models/station/station_qr_check_result.dart';
import '../../../domain/repositories/station_repository.dart';
import '../../../core/models/sensitive_action_intent.dart';

/// Coordinates station screens with typed station use cases.
class StationController extends FlowController {
  StationController({required StationRepositoryContract repository})
    : _repository = repository;

  final StationRepositoryContract _repository;

  Future<StationQrCheckResult> checkQr(Map<String, dynamic> params) =>
      execute('checkQr', () => _repository.checkQr(params));

  Future<void> cancelQr(
    Map<String, dynamic> params, {
    required String fallbackMessage,
  }) => execute(
    'cancelQr',
    () => _repository.cancelQr(params, fallbackMessage: fallbackMessage),
  );

  Future<StationConsumptionReceipt> consumeQr(
    Map<String, dynamic> params, {
    required String actionCode,
    required String scannedPublicCode,
    required String stationUserId,
    required String stationUserName,
    required String companyId,
    required String fallbackMessage,
    required String publicErrorMessage,
  }) => execute(
    'consumeQr',
    () => _repository.consumeQr(
      SensitiveActionIntent.create(
        'station-qr-use',
      ).withAuthParams(params, actionCode: actionCode),
      scannedPublicCode: scannedPublicCode,
      stationUserId: stationUserId,
      stationUserName: stationUserName,
      companyId: companyId,
      fallbackMessage: fallbackMessage,
      publicErrorMessage: publicErrorMessage,
    ),
  );

  Future<AcpecTransactionsPage> consumptionHistory({
    required Map<String, dynamic> params,
    required String userId,
    required String userName,
    required String companyId,
  }) => execute(
    'consumptionHistory',
    () => _repository.consumptionHistory(
      params: params,
      userId: userId,
      userName: userName,
      companyId: companyId,
    ),
  );

  Future<StationProfile> profile() => execute('profile', _repository.profile);

  Future<List<StationLocationItem>> stations() =>
      execute('stations', _repository.stations);

  void refreshProfile() => _repository.invalidateProfile();
}
