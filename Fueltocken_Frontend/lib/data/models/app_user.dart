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
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.phone,
    required this.role,
    this.companyId,
    this.stationId,
    required this.createdAt,
  });

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
    final telRaw = u['telephone']?.toString() ?? '';
    final telDigits = telRaw.replaceAll(RegExp(r'\D'), '');
    String phone = '';
    if (telDigits.length == 8) {
      phone = fullMrPhoneFromLocal8(telDigits);
    } else if (telRaw.isNotEmpty) {
      phone = telRaw.startsWith('+') ? telRaw : '+$telRaw';
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

    return AppUser(
      id: id,
      email: u['email']?.toString() ?? '',
      name: name,
      phone: phone,
      role: role,
      companyId: companyCode.isNotEmpty
          ? companyCode
          : AppBrandConfig.effectiveDefaultCompanyId,
      stationId: role == UserRole.station ? stationId : null,
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
      );
    }

    final idRaw = u['id'] ?? u['user_id'] ?? u['uid'];
    var id = idRaw?.toString() ?? '';
    if (id.isEmpty) {
      id = const Uuid().v4();
    }

    final fn = u['first_name']?.toString() ?? '';
    final ln = u['last_name']?.toString() ?? '';
    var name = (u['name'] ?? u['full_name'] ?? u['display_name'])?.toString() ?? '';
    if (name.isEmpty) {
      name = ('$fn $ln').trim();
    }
    if (name.isEmpty) {
      name = u['login']?.toString() ?? u['email']?.toString() ?? 'Utilisateur';
    }

    final telRaw =
        u['phone']?.toString() ?? u['mobile']?.toString() ?? u['telephone']?.toString() ?? '';
    final telDigits = telRaw.replaceAll(RegExp(r'\D'), '');
    String phone = '';
    if (telDigits.length == 8) {
      phone = fullMrPhoneFromLocal8(telDigits);
    } else if (telRaw.isNotEmpty) {
      phone = telRaw.startsWith('+') ? telRaw : '+$telRaw';
    }

    DateTime created = DateTime.now();
    final dj = u['date_joined'] ?? u['create_date'];
    if (dj is String) {
      created = DateTime.tryParse(dj) ?? created;
    }

    var companyCode = u['company_code']?.toString().trim() ??
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

    return AppUser(
      id: id,
      email: u['email']?.toString() ?? '',
      name: name,
      phone: phone,
      role: resolvedRole,
      companyId: companyCode.isNotEmpty
          ? companyCode
          : AppBrandConfig.effectiveDefaultCompanyId,
      stationId: resolvedRole == UserRole.station ? stationId : null,
      createdAt: created,
    );
  }

  AppUser copyWith({
    String? name,
    String? phone,
    UserRole? role,
    String? stationId,
    String? companyId,
  }) {
    return AppUser(
      id: id,
      email: email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      companyId: companyId ?? this.companyId,
      stationId: stationId ?? this.stationId,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [id, email, name, phone, role, companyId, stationId];

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
