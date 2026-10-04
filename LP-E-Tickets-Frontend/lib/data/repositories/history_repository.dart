import 'package:intl/intl.dart';

import '../../domain/models/history/business_transaction.dart';
import '../../domain/models/history/acpec_transactions_page.dart';
import '../../domain/models/purchase/carnet_catalog_load_result.dart';
import '../../domain/repositories/history_repository.dart';
import '../models/purchase_models/purchase_lot.dart';
import '../services/shared_services/odoo_fueltoken_facade.dart';
import '../services/history_services/acpec_transactions_mapper.dart';
import '../services/purchase_services/acpec_purchases_mapper.dart';
import '../services/purchase_services/acpec_carnet_catalog_service.dart';

class HistoryRepository implements HistoryRepositoryContract {
  HistoryRepository({OdooFueltokenFacade? api})
    : _api = api ?? OdooFueltokenFacade();
  final OdooFueltokenFacade _api;
  @override
  Future<AcpecTransactionsPage> page(
    Map<String, dynamic> params, {
    required bool station,
    required String userId,
    required String userName,
    required int limit,
    required int offset,
  }) async {
    final raw = station
        ? await _api.stationTransactions(params)
        : await _api.transactions(params);
    return AcpecTransactionsMapper.parsePage(
      raw,
      userId: userId,
      userName: userName,
      requestedLimit: limit,
      requestedOffset: offset,
    );
  }

  @override
  Future<List<BusinessTransaction>> submittedPurchases({
    required String userId,
    required String userName,
    required String companyId,
    required DateTime from,
    required DateTime to,
  }) async {
    const pageSize = 100;
    const maxPages = 100;
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final lots = <PurchaseLot>[];
    var offset = 0;

    for (var pageNumber = 0; pageNumber < maxPages; pageNumber++) {
      final raw = await _api.purchasesList({
        'limit': pageSize,
        'offset': offset,
        'date_from': dateFormat.format(start),
        'date_to': dateFormat.format(end),
        'include_pagination_meta': true,
      });
      final pageLots = AcpecPurchasesMapper.fromRpcResult(
        raw,
        clientId: userId,
        clientName: userName,
        companyId: companyId,
      );
      lots.addAll(pageLots);

      final metadata = _purchasePaginationMetadata(raw);
      final hasMore = metadata.hasMore ?? pageLots.length >= pageSize;
      if (!hasMore) break;
      final nextOffset = metadata.nextOffset ?? offset + pageSize;
      if (nextOffset <= offset) {
        throw const FormatException('Pagination des achats invalide.');
      }
      offset = nextOffset;
      if (pageNumber == maxPages - 1) {
        throw StateError(
          'L’historique des achats dépasse la pagination autorisée.',
        );
      }
    }

    final matchingLots = lots.where((lot) {
      final date = lot.submittedAt ?? lot.createdAt;
      return !date.isBefore(start) && !date.isAfter(end);
    }).toList();
    return AcpecTransactionsMapper.fromSubmittedPurchases(
      matchingLots,
      userId: userId,
      userName: userName,
    );
  }

  _PurchasePaginationMetadata _purchasePaginationMetadata(dynamic raw) {
    dynamic current = raw;
    for (var depth = 0; depth < 5 && current is Map; depth++) {
      final map = Map<String, dynamic>.from(current);
      final items = map['items'] ?? map['purchases'] ?? map['lots'];
      final hasMore = _asBool(map['has_more'] ?? map['hasMore']);
      final nextOffsetValue = map['next_offset'] ?? map['nextOffset'];
      final nextOffset = nextOffsetValue is num
          ? nextOffsetValue.toInt()
          : int.tryParse(nextOffsetValue?.toString() ?? '');
      if (items is List || hasMore != null || nextOffset != null) {
        return _PurchasePaginationMetadata(
          pageLength: items is List ? items.length : 0,
          hasMore: hasMore,
          nextOffset: nextOffset,
        );
      }
      current = map['data'] ?? map['result'];
    }
    return const _PurchasePaginationMetadata(pageLength: 0);
  }

  bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value == null) return null;
    switch (value.toString().trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
        return true;
      case 'false':
      case '0':
      case 'no':
        return false;
      default:
        return null;
    }
  }

  @override
  Future<AcpecCarnetCatalogLoadResult> catalog({required String companyId}) =>
      AcpecCarnetCatalogService.instance.loadMobileCatalogFacesOnly(
        companyId: companyId,
      );
  @override
  List<BusinessTransaction> localize(
    List<BusinessTransaction> transactions,
    AcpecCarnetCatalogLoadResult catalog,
  ) => AcpecCarnetCatalogService.localizeTransactionsByCarnetTypes(
    transactions: transactions,
    types: catalog.types,
  );

  @override
  bool matchesClientFilter(BusinessTransaction transaction, TxType filter) =>
      AcpecTransactionsMapper.matchesClientFilter(transaction, filter);
}

class _PurchasePaginationMetadata {
  const _PurchasePaginationMetadata({
    required this.pageLength,
    this.hasMore,
    this.nextOffset,
  });

  final int pageLength;
  final bool? hasMore;
  final int? nextOffset;
}
