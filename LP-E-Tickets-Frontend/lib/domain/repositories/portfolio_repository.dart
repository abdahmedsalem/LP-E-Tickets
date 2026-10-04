import '../models/portfolio/face_line.dart';
import '../models/qr/qr_token.dart';
import '../models/purchase/carnet_type.dart';
import '../models/purchase/carnet_catalog_load_result.dart';

abstract interface class PortfolioRepositoryContract {
  Future<List<CarnetType>> purchaseOfferTypes({required String companyId});
  Future<AcpecCarnetCatalogLoadResult> catalog({
    required String companyId,
    String? languageCode,
  });
  Future<List<FaceLine>> faces({
    required String ownerId,
    required String companyId,
    String? languageCode,
  });
  Future<List<QrToken>> qrs(
    Map<String, dynamic> params, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  });
  void invalidateQrs(Map<String, dynamic> params, {bool allVariants = false});
}
