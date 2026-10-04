import 'package:latlong2/latlong.dart';

import '../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../domain/models/history/acpec_transactions_page.dart';
import '../../domain/models/history/business_transaction.dart';
import '../../domain/models/purchase/carnet_catalog_load_result.dart';
import '../../domain/models/station/station_profile.dart';
import '../../domain/models/station/station_consumption_receipt.dart';
import '../../domain/models/station/station_location.dart';
import '../../domain/models/station/station_qr_check_result.dart';
import '../../domain/repositories/station_repository.dart';
import '../services/history_services/acpec_transactions_mapper.dart';
import '../services/purchase_services/acpec_carnet_catalog_service.dart';
import '../services/qr_services/acpec_qr_mapper.dart';
import '../services/station_services/station_qr_check_mapper.dart';
import '../services/station_services/acpec_station_profile_mapper.dart';
import '../services/shared_services/acpec_rpc_result_guard.dart';
import '../services/shared_services/odoo_fueltoken_facade.dart';

/// Data access and response mapping for station flows.
/// Screens depend on this repository through StationController only.
class StationRepository implements StationRepositoryContract {
  StationRepository({
    OdooFueltokenFacade? facade,
    AcpecCarnetCatalogService? catalogService,
  }) : _facade = facade ?? OdooFueltokenFacade(),
       _catalogService = catalogService ?? AcpecCarnetCatalogService.instance;

  final OdooFueltokenFacade _facade;
  final AcpecCarnetCatalogService _catalogService;

  @override
  Future<StationQrCheckResult> checkQr(Map<String, dynamic> params) async =>
      StationQrCheckMapper.fromRpc(await _facade.stationQrCheck(params));

  @override
  Future<void> cancelQr(
    Map<String, dynamic> params, {
    required String fallbackMessage,
  }) async {
    final raw = await _facade.stationQrCancel(params);
    acpecRpcMapOrThrow(raw, fallbackMessage: fallbackMessage);
  }

  @override
  Future<StationConsumptionReceipt> consumeQr(
    Map<String, dynamic> params, {
    required String scannedPublicCode,
    required String stationUserId,
    required String stationUserName,
    required String companyId,
    required String fallbackMessage,
    required String publicErrorMessage,
  }) async {
    final raw = await _facade.stationQrUse(params);
    final result = acpecRpcMapOrThrow(
      raw,
      fallbackMessage: fallbackMessage,
      publicErrorMessage: publicErrorMessage,
    );
    final routeCode =
        _firstString(result, const [
          'qr_public_code',
          'public_code',
          'publicCode',
        ]) ??
        scannedPublicCode;
    _invalidateConsumptionCaches(routeCode);

    return StationConsumptionReceipt(
      qr: AcpecQrMapper.fromStationUseResult(
        result,
        scannedPublicCode: scannedPublicCode,
        stationUserId: stationUserId,
        stationUserName: stationUserName,
        companyId: companyId,
      ),
      amount: _firstValue(result, const ['amount_total', 'amountTotal']),
      transactionName: _firstString(result, const [
        'transaction_name',
        'transactionName',
      ]),
      consumedAt:
          _firstDateTime(result, const [
            'consumed_at',
            'consumedAt',
            'transaction_created_at',
            'transactionCreatedAt',
            'created_at',
            'createdAt',
          ]) ??
          DateTime.now(),
      publicCode: routeCode,
    );
  }

  @override
  Future<AcpecTransactionsPage> consumptionHistory({
    required Map<String, dynamic> params,
    required String userId,
    required String userName,
    required String companyId,
  }) async {
    final catalogFuture = _catalogService
        .loadMobileCatalogFacesOnly(companyId: companyId)
        .catchError((_) => const AcpecCarnetCatalogLoadResult(types: []));
    final limit = (params['limit'] as int?) ?? 100;
    final offset = (params['offset'] as int?) ?? 0;
    final raw = await _facade.stationTransactions(params);
    final page = AcpecTransactionsMapper.parsePage(
      raw,
      userId: userId,
      userName: userName,
      requestedLimit: limit,
      requestedOffset: offset,
    );
    final catalog = await catalogFuture;
    final localized =
        AcpecCarnetCatalogService.localizeTransactionsByCarnetTypes(
            transactions: page.items,
            types: catalog.types,
          ).where((tx) => tx.type == TxType.stationConsumption).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return AcpecTransactionsPage(
      items: localized,
      totalCount: page.totalCount,
      totals: page.totals,
      hasMore: page.hasMore,
    );
  }

  @override
  Future<StationProfile> profile() async =>
      AcpecStationProfileMapper.fromRpc(await _facade.stationProfile(const {}));

  @override
  Future<List<StationLocationItem>> stations() async {
    final raw = await _facade.stationList();
    final items = _stationRows(raw);
    if (items == null) {
      throw const FormatException('Réponse de la liste des stations invalide.');
    }
    return items.map(_stationFromRow).toList(growable: false);
  }

  @override
  void invalidateProfile() {
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.stationProfile,
      const {},
    );
  }

  void _invalidateConsumptionCaches(String routeCode) {
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.qrDetail,
      AcpecQrMapper.detailParamsForRouteId(routeCode),
    );
    AcpecFueltokenRpcCoordinator.shared.invalidateRoute(
      OdooFueltokenRpcConfig.qrList,
    );
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.transactions,
      null,
    );
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.stationTransactions,
      null,
    );
    AcpecFueltokenRpcCoordinator.shared.invalidate(
      OdooFueltokenRpcConfig.walletCurrent,
      Map<String, dynamic>.from(
        OdooFueltokenRpcConfig.walletCurrentDefaultParams,
      ),
    );
  }

  List<Map<String, dynamic>>? _stationRows(dynamic raw) {
    dynamic payload = raw;
    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);
      payload = map['data'] ?? map;
      if (payload is Map) payload = payload['items'] ?? payload;
      if (payload is Map) payload = payload['stations'] ?? payload['items'];
    }
    if (payload is! List) return null;
    return payload.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  StationLocationItem _stationFromRow(Map<String, dynamic> row) {
    var latitude = (row['latitude'] as num?)?.toDouble() ?? 0;
    var longitude = (row['longitude'] as num?)?.toDouble() ?? 0;
    if (latitude == 0 && longitude == 0) {
      latitude = 18.0858;
      longitude = -15.9785;
    }
    final address = row['address']?.toString() ?? '';
    final addressLower = address.toLowerCase();
    final city = addressLower.contains('nouadhibou')
        ? 'Nouadhibou'
        : addressLower.contains('rosso')
        ? 'Rosso'
        : 'Nouakchott';
    return StationLocationItem(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? 'Station Leader Petroleum',
      city: city,
      address: address,
      phone: row['phone']?.toString() ?? '',
      location: LatLng(latitude, longitude),
    );
  }

  static Object? _firstValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key)) return data[key];
    }
    return null;
  }

  static String? _firstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null || value == false) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static DateTime? _firstDateTime(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
}
