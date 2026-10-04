import 'business_transaction.dart';

class AcpecTransactionsTotals {
  const AcpecTransactionsTotals({
    required this.qrCount,
    required this.transactionCount,
    required this.amountTotal,
    required this.qtyTotal,
    this.scope,
    this.regularizationState,
  });
  final int qrCount;
  final int transactionCount;
  final int amountTotal;
  final int qtyTotal;
  final String? scope;
  final String? regularizationState;
}

class AcpecTransactionsPage {
  const AcpecTransactionsPage({
    required this.items,
    this.totalCount,
    this.totals,
    required this.hasMore,
  });
  final List<BusinessTransaction> items;
  final int? totalCount;
  final AcpecTransactionsTotals? totals;
  final bool hasMore;
}
