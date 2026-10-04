/// Authenticated client data and runtime configuration passed to feature routes.
///
/// Screens receive this snapshot from the router instead of reading global
/// authentication and environment singletons directly.
class ClientSession {
  const ClientSession({
    required this.isLiveDataEnabled,
    required this.ownerId,
    required this.ownerName,
    required this.companyId,
    required this.ownerPhone,
    required this.isDeviceTrusted,
    this.stationName,
    this.stationId,
    this.ownerEmail = '',
  });

  final bool isLiveDataEnabled;
  final String? ownerId;
  final String ownerName;
  final String companyId;
  final String ownerPhone;
  final bool isDeviceTrusted;
  final String? stationName;
  final String? stationId;
  final String ownerEmail;
}
