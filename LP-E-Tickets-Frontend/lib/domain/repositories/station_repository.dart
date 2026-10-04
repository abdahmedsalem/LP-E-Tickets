import '../models/history/acpec_transactions_page.dart';
import '../models/station/station_profile.dart';
import '../models/station/station_consumption_receipt.dart';
import '../models/station/station_location.dart';
import '../models/station/station_qr_check_result.dart';

abstract interface class StationRepositoryContract {
  Future<StationQrCheckResult> checkQr(Map<String, dynamic> params);
  Future<void> cancelQr(
    Map<String, dynamic> params, {
    required String fallbackMessage,
  });
  Future<StationConsumptionReceipt> consumeQr(
    Map<String, dynamic> params, {
    required String scannedPublicCode,
    required String stationUserId,
    required String stationUserName,
    required String companyId,
    required String fallbackMessage,
    required String publicErrorMessage,
  });
  Future<AcpecTransactionsPage> consumptionHistory({
    required Map<String, dynamic> params,
    required String userId,
    required String userName,
    required String companyId,
  });
  Future<StationProfile> profile();
  Future<List<StationLocationItem>> stations();
  void invalidateProfile();
}
