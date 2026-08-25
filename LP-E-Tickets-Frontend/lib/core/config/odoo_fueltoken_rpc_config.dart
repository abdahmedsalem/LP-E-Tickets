/// Routes HTTP ACPEC FuelToken (`/api/acpec/...`). Surcharges via `--dart-define`.
class OdooFueltokenRpcConfig {
  OdooFueltokenRpcConfig._();

  static const String versionCheck = String.fromEnvironment(
    'ODOO_ACPEC_VERSION_PATH',
    defaultValue: '/api/acpec/mobile_auth/v1/version-check',
  );

  static const String signupCompanies = String.fromEnvironment(
    'ODOO_ACPEC_SIGNUP_COMPANIES_PATH',
    defaultValue: '/api/acpec/mobile_auth/v1/signup-companies',
  );

  static const String walletCurrent = String.fromEnvironment(
    'ODOO_RPC_FUEL_WALLET_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/wallet/current',
  );

  /// Paramètres par défaut pour l’alerte d’expiration du portefeuille.
  static const Map<String, dynamic> walletCurrentDefaultParams = {
    'near_expiration_days': 30,
    'near_expiration_limit': 10,
  };

  /// Historique paginé du portefeuille.
  static const String transactions = String.fromEnvironment(
    'ODOO_RPC_FUEL_TRANSACTIONS_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/transactions',
  );

  static const String transactionsDetail = String.fromEnvironment(
    'ODOO_RPC_FUEL_TRANSACTIONS_DETAIL_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/transactions/detail',
  );

  static const String purchasesCreate = String.fromEnvironment(
    'ODOO_RPC_FUEL_PURCHASES_CREATE_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/purchases/create',
  );

  static const String purchasesList = String.fromEnvironment(
    'ODOO_RPC_FUEL_PURCHASES_LIST_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/purchases',
  );

  static const String purchasesDetail = String.fromEnvironment(
    'ODOO_RPC_FUEL_PURCHASES_DETAIL_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/purchases/detail',
  );

  static const String paymentMethods = String.fromEnvironment(
    'ODOO_RPC_FUEL_PAYMENT_METHODS_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/payment-methods',
  );

  /// Achats en attente côté admin.
  static const String adminPurchasesPending = String.fromEnvironment(
    'ODOO_RPC_FUEL_ADMIN_PURCHASES_PENDING_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/admin/purchases/pending',
  );

  /// Détail d’un lot côté admin.
  static const String adminPurchasesDetail = String.fromEnvironment(
    'ODOO_RPC_FUEL_ADMIN_PURCHASES_DETAIL_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/admin/purchases/detail',
  );

  /// Validation d’un achat et génération des faces.
  static const String adminPurchasesApprove = String.fromEnvironment(
    'ODOO_RPC_FUEL_ADMIN_PURCHASES_APPROVE_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/admin/purchases/approve',
  );

  /// Liste des stations (admin).
  static const String adminStationsList = String.fromEnvironment(
    'ODOO_RPC_FUEL_ADMIN_STATIONS_LIST_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/admin/stations/list',
  );

  /// Résumé global admin.
  static const String adminReportsSummary = String.fromEnvironment(
    'ODOO_RPC_FUEL_ADMIN_REPORTS_SUMMARY_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/admin/reports/summary',
  );

  static const String faces = String.fromEnvironment(
    'ODOO_RPC_FUEL_FACES_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/faces',
  );

  /// Types de carnets (mobile).
  static const String carnetTypes = String.fromEnvironment(
    'ODOO_RPC_FUEL_CARNET_TYPES_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/carnet-types',
  );

  /// Liste des types de carnets (admin).
  static const String adminCarnetTypesList = String.fromEnvironment(
    'ODOO_RPC_FUEL_ADMIN_CARNET_TYPES_LIST_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/admin/carnet-types/list',
  );

  static const String qrIssue = String.fromEnvironment(
    'ODOO_RPC_FUEL_QR_ISSUE_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/qr/issue',
  );

  static const String qrList = String.fromEnvironment(
    'ODOO_RPC_FUEL_QR_LIST_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/qr/list',
  );

  static const String qrDetail = String.fromEnvironment(
    'ODOO_RPC_FUEL_QR_DETAIL_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/qr/detail',
  );

  static const String qrRevealCode = String.fromEnvironment(
    'ODOO_RPC_FUEL_QR_REVEAL_CODE_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/qr/reveal-code',
  );

  static const String qrRetirer = String.fromEnvironment(
    'ODOO_RPC_FUEL_QR_RETIRER_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/qr/retirer',
  );

  static const String qrSeparer = String.fromEnvironment(
    'ODOO_RPC_FUEL_QR_SEPARER_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/qr/separer',
  );

  static const String carnetsTransfer = String.fromEnvironment(
    'ODOO_RPC_FUEL_CARNETS_TRANSFER_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/carnets/transfer',
  );

  static const String carnetsTransferRecipient = String.fromEnvironment(
    'ODOO_RPC_FUEL_CARNETS_TRANSFER_RECIPIENT_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/carnets/transfer/recipient',
  );

  static const String ticketsTransfer = String.fromEnvironment(
    'ODOO_RPC_FUEL_TICKETS_TRANSFER_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/mobile/tickets/transfer',
  );

  static const String stationQrUse = String.fromEnvironment(
    'ODOO_RPC_FUEL_STATION_QR_USE_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/station/qr/use',
  );

  /// Historique des consommations côté station.
  static const String stationTransactions = String.fromEnvironment(
    'ODOO_RPC_FUEL_STATION_TRANSACTIONS_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/station/transactions',
  );

  /// Profil station et opérateur lié.
  static const String stationProfile = String.fromEnvironment(
    'ODOO_RPC_FUEL_STATION_PROFILE_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/station/profile',
  );

  /// Vérification d’un QR avant consommation.
  static const String stationQrCheck = String.fromEnvironment(
    'ODOO_RPC_FUEL_STATION_QR_CHECK_PATH',
    defaultValue: '/api/acpec/fueltoken/v1/station/qr/check',
  );
}
