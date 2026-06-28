import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_brand_config.dart';
import '../../core/validation/contact_validators.dart';
import 'acpec_user_role_resolver.dart';
import 'user_role.dart';

class AppUser extends Equatable {
  final String id;
  final String email;
  final String name;
  final String phone;
  final UserRole role;
  final String? companyId;
  final String? stationId;

  /// Nom de la station ou de la société affecté à cet utilisateur station.
  final String? stationName;

  /// État de confiance du device mobile côté backend ACPEC.
  ///
  /// Absence de valeur = ancien payload / mode local : ne bloque pas l'application.
  /// Valeurs attendues côté backend : trusted, pending_trust, pending_approval, rejected, blocked.
  final String? deviceTrustState;
  final bool? deviceTrustRequiredForSensitive;

  final DateTime createdAt;

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

  static String _safeText(dynamic value) {
    if (value == null || value == false) return '';
    final s = value.toString().trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower == 'false' || lower == 'null') return '';
    return s;
  }

  static String _firstSafeText(List<dynamic> values) {
    for (final value in values) {
      final s = _safeText(value);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static List<Map<String, dynamic>?> _candidateTrustMaps(
    Map<String, dynamic> userPayload, {
    Map<String, dynamic>? raw,
    Map<String, dynamic>? envelope,
  }) {
    final maps = <Map<String, dynamic>?>[
      userPayload,
      raw,
      envelope,
      _mapOrNull(userPayload['device']),
      _mapOrNull(userPayload['mobile_device']),
      _mapOrNull(raw?['user']),
      _mapOrNull(raw?['data']),
      _mapOrNull(raw?['device']),
      _mapOrNull(raw?['mobile_device']),
      _mapOrNull(envelope?['user']),
      _mapOrNull(envelope?['data']),
      _mapOrNull(envelope?['device']),
      _mapOrNull(envelope?['mobile_device']),
    ];
    final envelopeData = _mapOrNull(envelope?['data']);
    maps.add(_mapOrNull(envelopeData?['user']));
    maps.add(_mapOrNull(envelopeData?['device']));
    maps.add(_mapOrNull(envelopeData?['mobile_device']));
    return maps;
  }

  static String? _firstSafeTextInMaps(
    List<Map<String, dynamic>?> maps,
    List<String> keys,
  ) {
    for (final map in maps) {
      if (map == null) continue;
      for (final key in keys) {
        final value = _safeText(map[key]);
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static bool? _safeBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = _safeText(value).toLowerCase();
    if (s.isEmpty) return null;
    if (['true', '1', 'yes', 'y', 'oui'].contains(s)) return true;
    if (['false', '0', 'no', 'n', 'non'].contains(s)) return false;
    return null;
  }

  static bool? _firstBoolInMaps(
    List<Map<String, dynamic>?> maps,
    List<String> keys,
  ) {
    for (final map in maps) {
      if (map == null) continue;
      for (final key in keys) {
        final value = _safeBool(map[key]);
        if (value != null) return value;
      }
    }
    return null;
  }

  static String? _resolveDeviceTrustState(
    Map<String, dynamic> userPayload, {
    Map<String, dynamic>? raw,
    Map<String, dynamic>? envelope,
  }) {
    return _firstSafeTextInMaps(
      _candidateTrustMaps(userPayload, raw: raw, envelope: envelope),
      const [
        'device_trust_state',
        'deviceTrustState',
        'mobile_device_trust_state',
        'mobileDeviceTrustState',
      ],
    );
  }

  static bool? _resolveDeviceTrustRequiredForSensitive(
    Map<String, dynamic> userPayload, {
    Map<String, dynamic>? raw,
    Map<String, dynamic>? envelope,
  }) {
    return _firstBoolInMaps(
      _candidateTrustMaps(userPayload, raw: raw, envelope: envelope),
      const [
        'device_trust_required_for_sensitive',
        'deviceTrustRequiredForSensitive',
        'mobile_device_trust_required_for_sensitive',
        'mobileDeviceTrustRequiredForSensitive',
      ],
    );
  }

  /// Profil issu du flux d’inscription (JWT) ou du profil Odoo.
  factory AppUser.fromOtpApiUserJson(Map<String, dynamic> u) {
    final idRaw = u['id_utilisateur'];
    var id = idRaw?.toString() ?? '';
    if (id.isEmpty) {
      id = const Uuid().v4();
    }
    final fn = u['first_name']?.toString() ?? '';
    final ln = u['last_name']?.toString() ?? '';
    var name = ('$fn $ln').trim();
    if (name.isEmpty) {
      name = u['username']?.toString() ?? 'Utilisateur';
    }
    final telRaw = _firstSafeText([
      u['mobile_phone'],
      u['phone'],
      u['mobile'],
      u['telephone'],
    ]);
    final localDigits = localMrDigitsFromFull(telRaw);
    String phone = '';
    if (kMrLocalPhoneDigits.hasMatch(localDigits)) {
      phone = localDigits;
    }

    final type = u['type_utilisateur']?.toString() ?? 'Client';
    final roleField = u['role']?.toString().toLowerCase() ?? '';
    var role = UserRole.user;
    if (roleField == 'admin') {
      role = UserRole.admin;
    } else if (roleField == 'station') {
      role = UserRole.station;
    } else if (type == 'Administrateur') {
      role = UserRole.admin;
    }

    final resolved = AcpecUserRoleResolver.resolve(userPayload: u, envelope: u);
    role = _higherPrivilegeRole(role, resolved);

    DateTime created = DateTime.now();
    final dj = u['date_joined'];
    if (dj is String) {
      created = DateTime.tryParse(dj) ?? created;
    }

    var companyCode = u['company_code']?.toString().trim() ?? '';
    if (companyCode == 'leader') {
      companyCode = AppBrandConfig.effectiveDefaultCompanyId;
    }
    final sidRaw = u['station_id'];
    String? stationId;
    if (sidRaw != null) {
      final s = sidRaw.toString().trim();
      stationId = s.isEmpty ? null : s;
    }
    final snRaw = u['station_name'] ?? u['company_name'] ?? u['partner_name'];
    final stationName = snRaw?.toString().trim();
    final deviceTrustState = _resolveDeviceTrustState(u);
    final deviceTrustRequiredForSensitive =
        _resolveDeviceTrustRequiredForSensitive(u);

    return AppUser(
      id: id,
      email: _safeText(u['email']),
      name: name,
      phone: phone,
      role: role,
      companyId: companyCode.isNotEmpty
          ? companyCode
          : AppBrandConfig.effectiveDefaultCompanyId,
      stationId: role == UserRole.station ? stationId : null,
      stationName: role == UserRole.station
          ? (stationName?.isNotEmpty == true ? stationName : null)
          : null,
      deviceTrustState: deviceTrustState,
      deviceTrustRequiredForSensitive: deviceTrustRequiredForSensitive,
      createdAt: created,
    );
  }

  /// Profil issu d’une réponse JSON-RPC Odoo (`login`, `session_me`, etc.).
  ///
  /// Accepte soit une carte « utilisateur » directe, soit `{ "user": { ... } }`.
  /// Si les clés ressemblent à un profil issu d’une API REST historique (`id_utilisateur`, …), on réutilise
  /// [fromOtpApiUserJson] puis on **recalcule le rôle** via [AcpecUserRoleResolver]
  /// (champs Odoo : `is_superuser`, `groups`, `user_type`, etc.).
  ///
  /// [envelope] : réponse RPC avant extraction de `data` (pour champs hors `user`).
  factory AppUser.fromOdooProfileMap(
    Map<String, dynamic> raw, {
    Map<String, dynamic>? envelope,
  }) {
    Map<String, dynamic> u = raw;
    final nested = raw['user'];
    if (nested is Map) {
      u = Map<String, dynamic>.from(nested);
    }

    final resolvedRole = AcpecUserRoleResolver.resolve(
      userPayload: u,
      envelope: envelope ?? raw,
    );

    if (u.containsKey('id_utilisateur') ||
        (u.containsKey('first_name') && u.containsKey('email'))) {
      final base = AppUser.fromOtpApiUserJson(u);
      return base.copyWith(
        role: _higherPrivilegeRole(base.role, resolvedRole),
        deviceTrustState: _resolveDeviceTrustState(
          u,
          raw: raw,
          envelope: envelope,
        ),
        deviceTrustRequiredForSensitive:
            _resolveDeviceTrustRequiredForSensitive(
              u,
              raw: raw,
              envelope: envelope,
            ),
      );
    }

    final idRaw = u['id'] ?? u['user_id'] ?? u['uid'];
    var id = idRaw?.toString() ?? '';
    if (id.isEmpty) {
      id = const Uuid().v4();
    }

    final fn = u['first_name']?.toString() ?? '';
    final ln = u['last_name']?.toString() ?? '';
    var name =
        (u['name'] ?? u['full_name'] ?? u['display_name'])?.toString() ?? '';
    if (name.isEmpty) {
      name = ('$fn $ln').trim();
    }
    if (name.isEmpty) {
      name = u['login']?.toString() ?? u['email']?.toString() ?? 'Utilisateur';
    }

    final telRaw = _firstSafeText([
      u['mobile_phone'],
      u['phone'],
      u['mobile'],
      u['telephone'],
    ]);
    final localDigits = localMrDigitsFromFull(telRaw);
    String phone = '';
    if (kMrLocalPhoneDigits.hasMatch(localDigits)) {
      phone = localDigits;
    }

    DateTime created = DateTime.now();
    final dj = u['date_joined'] ?? u['create_date'];
    if (dj is String) {
      created = DateTime.tryParse(dj) ?? created;
    }

    var companyCode =
        u['company_code']?.toString().trim() ??
        u['company_id']?.toString().trim() ??
        '';
    if (companyCode == 'leader') {
      companyCode = AppBrandConfig.effectiveDefaultCompanyId;
    }
    final sidRaw = u['station_id'];
    String? stationId;
    if (sidRaw != null) {
      final s = sidRaw.toString().trim();
      stationId = s.isEmpty ? null : s;
    }
    final snRaw2 = u['station_name'] ?? u['company_name'] ?? u['partner_name'];
    final stationName2 = snRaw2?.toString().trim();
    final deviceTrustState = _resolveDeviceTrustState(
      u,
      raw: raw,
      envelope: envelope,
    );
    final deviceTrustRequiredForSensitive =
        _resolveDeviceTrustRequiredForSensitive(
          u,
          raw: raw,
          envelope: envelope,
        );

    return AppUser(
      id: id,
      email: _safeText(u['email']),
      name: name,
      phone: phone,
      role: resolvedRole,
      companyId: companyCode.isNotEmpty
          ? companyCode
          : AppBrandConfig.effectiveDefaultCompanyId,
      stationId: resolvedRole == UserRole.station ? stationId : null,
      stationName: resolvedRole == UserRole.station
          ? (stationName2?.isNotEmpty == true ? stationName2 : null)
          : null,
      deviceTrustState: deviceTrustState,
      deviceTrustRequiredForSensitive: deviceTrustRequiredForSensitive,
      createdAt: created,
    );
  }

  String? get normalizedDeviceTrustState {
    final state = deviceTrustState?.trim().toLowerCase();
    if (state == null || state.isEmpty) return null;
    return state;
  }

  bool get isDeviceTrusted {
    final state = normalizedDeviceTrustState;
    if (state == null) return true; // legacy/local payload: do not block.
    return state == 'trusted';
  }

  bool get isDeviceBlocked {
    final state = normalizedDeviceTrustState;
    return state == 'blocked' || state == 'rejected';
  }

  bool get isDeviceActivationPending {
    final state = normalizedDeviceTrustState;
    if (state == null || state == 'trusted') return false;
    if (isDeviceBlocked) return false;
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
  }) {
    return AppUser(
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
          deviceTrustRequiredForSensitive ??
          this.deviceTrustRequiredForSensitive,
      createdAt: createdAt,
    );
  }

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

  /// Garde le rôle le plus élevé (ex. profil « client » + drapeaux ACPEC admin).
  static UserRole _higherPrivilegeRole(UserRole a, UserRole b) {
    int rank(UserRole x) => switch (x) {
      UserRole.admin => 2,
      UserRole.station => 1,
      UserRole.user => 0,
    };
    return rank(a) >= rank(b) ? a : b;
  }
}
