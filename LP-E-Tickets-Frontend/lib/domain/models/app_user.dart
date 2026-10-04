import 'package:equatable/equatable.dart';

import 'user_role.dart';

/// Authenticated application user, independent of the API payload format.
class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.phone,
    required this.role,
    this.companyId,
    this.stationId,
    this.stationName,
    this.deviceTrustState,
    this.deviceTrustRequiredForSensitive,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String name;
  final String phone;
  final UserRole role;
  final String? companyId;
  final String? stationId;
  final String? stationName;
  final String? deviceTrustState;
  final bool? deviceTrustRequiredForSensitive;
  final DateTime createdAt;

  String? get normalizedDeviceTrustState {
    final state = deviceTrustState?.trim().toLowerCase();
    if (state == null || state.isEmpty) return null;
    return state;
  }

  bool get isDeviceTrusted {
    final state = normalizedDeviceTrustState;
    if (state == null) return true;
    return state == 'trusted';
  }

  bool get isDeviceBlocked {
    final state = normalizedDeviceTrustState;
    return state == 'blocked' || state == 'rejected';
  }

  bool get isDeviceActivationPending {
    final state = normalizedDeviceTrustState;
    if (state == null || state == 'trusted' || isDeviceBlocked) return false;
    return state == 'pending_trust' ||
        state == 'pending_approval' ||
        state == 'pending';
  }

  AppUser copyWith({
    String? name,
    String? phone,
    UserRole? role,
    String? stationId,
    String? companyId,
    String? stationName,
    String? deviceTrustState,
    bool? deviceTrustRequiredForSensitive,
  }) => AppUser(
    id: id,
    email: email,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    role: role ?? this.role,
    companyId: companyId ?? this.companyId,
    stationId: stationId ?? this.stationId,
    stationName: stationName ?? this.stationName,
    deviceTrustState: deviceTrustState ?? this.deviceTrustState,
    deviceTrustRequiredForSensitive:
        deviceTrustRequiredForSensitive ?? this.deviceTrustRequiredForSensitive,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    email,
    name,
    phone,
    role,
    companyId,
    stationId,
    stationName,
    deviceTrustState,
    deviceTrustRequiredForSensitive,
  ];
}
