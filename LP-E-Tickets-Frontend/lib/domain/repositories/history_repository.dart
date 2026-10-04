import '../models/history/business_transaction.dart';
import '../models/history/acpec_transactions_page.dart';
import '../models/purchase/carnet_catalog_load_result.dart';

abstract interface class HistoryRepositoryContract {
  Future<AcpecTransactionsPage> page(
    Map<String, dynamic> params, {
    required bool station,
    required String userId,
    required String userName,
    required int limit,
    required int offset,
  });
  Future<List<BusinessTransaction>> submittedPurchases({
    required String userId,
    required String userName,
    required String companyId,
    required DateTime from,
    required DateTime to,
  });
  Future<AcpecCarnetCatalogLoadResult> catalog({required String companyId});
  List<BusinessTransaction> localize(
    List<BusinessTransaction> transactions,
    AcpecCarnetCatalogLoadResult catalog,
  );
  bool matchesClientFilter(BusinessTransaction transaction, TxType filter);
}
