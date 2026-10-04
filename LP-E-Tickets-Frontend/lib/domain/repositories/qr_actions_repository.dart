import '../models/qr/qr_token.dart';

abstract interface class QrActionsRepositoryContract {
  Future<QrToken> loadDetail(
    String routeId, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  });
  QrToken parseQr(
    dynamic raw, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  });
  void invalidateDetail(String routeId);
  void invalidateList();
  Future<Map<String, dynamic>> qrSeparer(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  });
  Future<Map<String, dynamic>> qrRetirer(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  });
  Future<Map<String, dynamic>> qrRevealCode(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  });
}
