import '../../../core/controllers/flow_controller.dart';
import '../../../domain/repositories/portfolio_repository.dart';
import '../../../domain/models/portfolio/face_line.dart';
import '../../../domain/models/qr/qr_token.dart';
import '../../../domain/models/purchase/carnet_type.dart';
import '../../../domain/models/purchase/carnet_catalog_load_result.dart';

class PortfolioController extends FlowController {
  PortfolioController({required PortfolioRepositoryContract repository})
    : _repository = repository;
  final PortfolioRepositoryContract _repository;
  Future<List<CarnetType>> purchaseOfferTypes({required String companyId}) =>
      execute(
        'purchaseOfferTypes',
        () => _repository.purchaseOfferTypes(companyId: companyId),
      );
  Future<AcpecCarnetCatalogLoadResult> catalog({
    required String companyId,
    String? languageCode,
  }) => execute(
    'catalog',
    () => _repository.catalog(companyId: companyId, languageCode: languageCode),
  );
  Future<List<FaceLine>> faces({
    required String ownerId,
    required String companyId,
    String? languageCode,
  }) => execute(
    'faces',
    () => _repository.faces(
      ownerId: ownerId,
      companyId: companyId,
      languageCode: languageCode,
    ),
  );
  Future<List<QrToken>> qrs(
    Map<String, dynamic> params, {
    required String ownerId,
    required String ownerName,
    required String companyId,
  }) => execute(
    'qrs',
    () => _repository.qrs(
      params,
      ownerId: ownerId,
      ownerName: ownerName,
      companyId: companyId,
    ),
  );
  void invalidateQrs(Map<String, dynamic> params, {bool allVariants = false}) =>
      _repository.invalidateQrs(params, allVariants: allVariants);
}
