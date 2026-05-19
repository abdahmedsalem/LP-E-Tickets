import '../../core/config/odoo_fueltoken_rpc_config.dart';
import '../api/acpec_fueltoken_jsonrpc_api.dart';

/// Route ACPEC absente ou désactivée (`dart-define` vide après trim).
class OdooFuelRpcNotConfigured implements Exception {
  OdooFuelRpcNotConfigured(this.settingHint);

  final String settingHint;

  @override
  String toString() =>
      'OdooFuelRpcNotConfigured: définir $settingHint (chemin route ACPEC, ex. /api/acpec/...).';
}

/// Façade des appels Odoo FuelToken et administration.
class OdooFueltokenFacade {
  OdooFueltokenFacade({AcpecFueltokenJsonRpcApi? api})
      : _api = api ?? AcpecFueltokenJsonRpcApi();

  final AcpecFueltokenJsonRpcApi _api;

  Future<dynamic> _call(String route, String defineHint,
      [Map<String, dynamic>? params]) {
    final r = route.trim();
    if (r.isEmpty) {
      throw OdooFuelRpcNotConfigured(defineHint);
    }
    return _api.callRoute(r, params: params ?? const {});
  }

  Future<dynamic> versionCheck([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.versionCheck,
        'ODOO_ACPEC_VERSION_PATH',
        params,
      );

  Future<dynamic> signupCompanies([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.signupCompanies,
        'ODOO_ACPEC_SIGNUP_COMPANIES_PATH',
        params,
      );

  Future<dynamic> walletCurrent([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.walletCurrent,
        'ODOO_RPC_FUEL_WALLET_PATH',
        params,
      );

  Future<dynamic> transactions(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.transactions,
        'ODOO_RPC_FUEL_TRANSACTIONS_PATH',
        params,
      );

  Future<dynamic> transactionsDetail(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.transactionsDetail,
        'ODOO_RPC_FUEL_TRANSACTIONS_DETAIL_PATH',
        params,
      );

  Future<dynamic> purchasesCreate(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.purchasesCreate,
        'ODOO_RPC_FUEL_PURCHASES_CREATE_PATH',
        params,
      );

  Future<dynamic> purchasesList([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.purchasesList,
        'ODOO_RPC_FUEL_PURCHASES_LIST_PATH',
        params,
      );

  Future<dynamic> purchasesDetail(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.purchasesDetail,
        'ODOO_RPC_FUEL_PURCHASES_DETAIL_PATH',
        params,
      );

  Future<dynamic> adminPurchasesPending(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.adminPurchasesPending,
        'ODOO_RPC_FUEL_ADMIN_PURCHASES_PENDING_PATH',
        params,
      );

  Future<dynamic> adminPurchasesDetail(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.adminPurchasesDetail,
        'ODOO_RPC_FUEL_ADMIN_PURCHASES_DETAIL_PATH',
        params,
      );

  Future<dynamic> adminPurchasesApprove(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.adminPurchasesApprove,
        'ODOO_RPC_FUEL_ADMIN_PURCHASES_APPROVE_PATH',
        params,
      );

  Future<dynamic> adminPurchasesReject(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.adminPurchasesReject,
        'ODOO_RPC_FUEL_ADMIN_PURCHASES_REJECT_PATH',
        params,
      );

  Future<dynamic> adminStationsList([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.adminStationsList,
        'ODOO_RPC_FUEL_ADMIN_STATIONS_LIST_PATH',
        params ?? const {},
      );

  Future<dynamic> adminStationsCreate(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.adminStationsCreate,
        'ODOO_RPC_FUEL_ADMIN_STATIONS_CREATE_PATH',
        params,
      );

  Future<dynamic> adminStationsUpdate(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.adminStationsUpdate,
        'ODOO_RPC_FUEL_ADMIN_STATIONS_UPDATE_PATH',
        params,
      );

  Future<dynamic> adminStationsDisable(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.adminStationsDisable,
        'ODOO_RPC_FUEL_ADMIN_STATIONS_DISABLE_PATH',
        params,
      );

  Future<dynamic> adminReportsSummary([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.adminReportsSummary,
        'ODOO_RPC_FUEL_ADMIN_REPORTS_SUMMARY_PATH',
        params ?? const {},
      );

  Future<dynamic> faces([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.faces,
        'ODOO_RPC_FUEL_FACES_PATH',
        params,
      );

  Future<dynamic> carnetTypes([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.carnetTypes,
        'ODOO_RPC_FUEL_CARNET_TYPES_PATH',
        params,
      );

  Future<dynamic> adminCarnetTypesList([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.adminCarnetTypesList,
        'ODOO_RPC_FUEL_ADMIN_CARNET_TYPES_LIST_PATH',
        params,
      );

  Future<dynamic> adminCarnetTypesCreate(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.adminCarnetTypesCreate,
        'ODOO_RPC_FUEL_ADMIN_CARNET_TYPES_CREATE_PATH',
        params,
      );

  Future<dynamic> adminCarnetTypesUpdate(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.adminCarnetTypesUpdate,
        'ODOO_RPC_FUEL_ADMIN_CARNET_TYPES_UPDATE_PATH',
        params,
      );

  Future<dynamic> adminCarnetTypesDelete(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.adminCarnetTypesDelete,
        'ODOO_RPC_FUEL_ADMIN_CARNET_TYPES_DELETE_PATH',
        params,
      );

  Future<dynamic> qrIssue(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.qrIssue,
        'ODOO_RPC_FUEL_QR_ISSUE_PATH',
        params,
      );

  Future<dynamic> qrList([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.qrList,
        'ODOO_RPC_FUEL_QR_LIST_PATH',
        params,
      );

  Future<dynamic> qrDetail(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.qrDetail,
        'ODOO_RPC_FUEL_QR_DETAIL_PATH',
        params,
      );

  Future<dynamic> qrSplit(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.qrSplit,
        'ODOO_RPC_FUEL_QR_SPLIT_PATH',
        params,
      );

  Future<dynamic> stationQrUse(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.stationQrUse,
        'ODOO_RPC_FUEL_STATION_QR_USE_PATH',
        params,
      );

  Future<dynamic> stationTransactions(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.stationTransactions,
        'ODOO_RPC_FUEL_STATION_TRANSACTIONS_PATH',
        params,
      );

  Future<dynamic> stationProfile([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.stationProfile,
        'ODOO_RPC_FUEL_STATION_PROFILE_PATH',
        params ?? const {},
      );

  Future<dynamic> stationQrCheck(Map<String, dynamic> params) => _call(
        OdooFueltokenRpcConfig.stationQrCheck,
        'ODOO_RPC_FUEL_STATION_QR_CHECK_PATH',
        params,
      );

  Future<dynamic> adminAccountRequests([Map<String, dynamic>? params]) => _call(
        OdooFueltokenRpcConfig.adminAccountRequests,
        'ODOO_ACPEC_ADMIN_ACCOUNT_REQUESTS_PATH',
        params,
      );

  Future<dynamic> adminApproveAccountRequest(int requestId,
          [Map<String, dynamic>? params]) =>
      _api.callRoute(
        OdooFueltokenRpcConfig.adminAccountApproveRoute(requestId),
        params: params ?? const {},
      );

  Future<dynamic> adminRejectAccountRequest(
    int requestId,
    Map<String, dynamic> params,
  ) =>
      _api.callRoute(
        OdooFueltokenRpcConfig.adminAccountRejectRoute(requestId),
        params: params,
      );
}
