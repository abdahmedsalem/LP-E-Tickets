import 'package:equatable/equatable.dart';

import '../app_user.dart';

/// Station and operator details needed by station-facing screens.
class StationProfile extends Equatable {
  const StationProfile({
    required this.stationId,
    required this.stationName,
    required this.stationCode,
    required this.stationAddress,
    required this.stationActive,
    required this.operatorName,
    required this.operatorEmail,
    required this.operatorPhone,
    required this.operatorId,
  });

  final String stationId;
  final String stationName;
  final String stationCode;
  final String stationAddress;
  final bool stationActive;
  final String operatorName;
  final String operatorEmail;
  final String operatorPhone;
  final String operatorId;

  factory StationProfile.fromSessionUser(AppUser user) =>
      StationProfile.fromSessionDetails(
        stationName: user.stationName,
        stationId: user.stationId,
        operatorName: user.name,
        operatorEmail: user.email,
        operatorPhone: user.phone,
        operatorId: user.id,
      );

  factory StationProfile.fromSessionDetails({
    required String? stationName,
    required String? stationId,
    required String operatorName,
    required String operatorEmail,
    required String operatorPhone,
    required String operatorId,
  }) {
    final rawName = (stationName ?? '').trim();
    final resolvedName = _isGenericCompanyName(rawName) ? '' : rawName;
    final resolvedId = (stationId ?? '').trim();
    final resolvedOperator = operatorName.trim();

    return StationProfile(
      stationId: resolvedId.isEmpty ? '—' : resolvedId,
      stationName: resolvedName.isEmpty ? 'Station' : resolvedName,
      stationCode: resolvedId.isEmpty ? '—' : resolvedId,
      stationAddress: '—',
      stationActive: true,
      operatorName: resolvedOperator.isEmpty
          ? 'Opérateur station'
          : resolvedOperator,
      operatorEmail: operatorEmail.trim(),
      operatorPhone: operatorPhone.trim(),
      operatorId: operatorId.trim().isEmpty ? '—' : operatorId.trim(),
    );
  }

  static bool _isGenericCompanyName(String value) {
    final normalized = value.toLowerCase().trim();
    if (normalized.isEmpty) return true;
    return normalized == 'my company' ||
        normalized == 'your company' ||
        normalized == 'company' ||
        normalized == 'ma société' ||
        normalized == 'ma societe' ||
        normalized == 'société' ||
        normalized == 'societe';
  }

  @override
  List<Object?> get props => [
    stationId,
    stationName,
    stationCode,
    stationAddress,
    stationActive,
    operatorName,
    operatorEmail,
    operatorPhone,
    operatorId,
  ];
}
