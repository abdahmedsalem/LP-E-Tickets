import '../../../core/controllers/flow_controller.dart';
import '../../../domain/repositories/history_repository.dart';
import '../../../domain/models/history/business_transaction.dart';
import '../../../domain/models/history/acpec_transactions_page.dart';
import '../../../domain/models/purchase/carnet_catalog_load_result.dart';

/// Shared by the Operations and History tabs.
class HistoryController extends FlowController {
  HistoryController({required HistoryRepositoryContract repository})
    : _repository = repository;
  final HistoryRepositoryContract _repository;
  Future<AcpecTransactionsPage> page(
    Map<String, dynamic> params, {
    required bool station,
    required String userId,
    required String userName,
    required int limit,
    required int offset,
  }) => execute(
    'page:$offset',
    () => _repository.page(
      params,
      station: station,
      userId: userId,
      userName: userName,
      limit: limit,
      offset: offset,
    ),
  );
  Future<List<BusinessTransaction>> submittedPurchases({
    required String userId,
    required String userName,
    required String companyId,
    required DateTime from,
    required DateTime to,
  }) => execute(
    'purchases',
    () => _repository.submittedPurchases(
      userId: userId,
      userName: userName,
      companyId: companyId,
      from: from,
      to: to,
    ),
  );
  Future<AcpecCarnetCatalogLoadResult> catalog({required String companyId}) =>
      execute('catalog', () => _repository.catalog(companyId: companyId));
  List<BusinessTransaction> localize(
    List<BusinessTransaction> transactions,
    AcpecCarnetCatalogLoadResult catalog,
  ) => _repository.localize(transactions, catalog);

  bool matchesClientFilter(BusinessTransaction transaction, TxType filter) =>
      _repository.matchesClientFilter(transaction, filter);
}
