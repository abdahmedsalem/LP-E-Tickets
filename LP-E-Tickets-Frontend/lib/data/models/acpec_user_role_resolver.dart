import 'user_role.dart';

/// Déduit le [UserRole] à partir des champs renvoyés par ACPEC / Odoo (login, session-check).
///
/// Aucun compte codé en dur : uniquement les clés présentes dans la réponse API.
class AcpecUserRoleResolver {
  AcpecUserRoleResolver._();

  /// [userPayload] : objet `user` ou carte profil ; [envelope] : réponse complète (ex. login RPC).
  static UserRole resolve({
    required Map<String, dynamic> userPayload,
    Map<String, dynamic>? envelope,
  }) {
    final sources = <Map<String, dynamic>>[];
    if (envelope != null) {
      sources.add(envelope);
      final d = envelope['data'];
      if (d is Map) {
        sources.add(Map<String, dynamic>.from(d));
      }
      final sess = envelope['session'];
      if (sess is Map) {
        sources.add(Map<String, dynamic>.from(sess));
      }
    }
    sources.add(userPayload);

    final p = userPayload['partner'];
    if (p is Map) {
      sources.add(Map<String, dynamic>.from(p));
    }
    final profile = userPayload['profile'];
    if (profile is Map) {
      sources.add(Map<String, dynamic>.from(profile));
    }

    UserRole best = UserRole.user;
    for (final m in sources) {
      final r = _fromSingleMap(m);
      if (r != null) {
        best = _higherPrivilege(best, r);
      }
    }
    return best;
  }

  static UserRole _higherPrivilege(UserRole a, UserRole b) {
    int rank(UserRole x) => switch (x) {
      UserRole.admin => 2,
      UserRole.station => 1,
      UserRole.user => 0,
    };
    return rank(b) > rank(a) ? b : a;
  }

  static UserRole? _fromSingleMap(Map<String, dynamic> m) {
    if (_truthy(m['is_superuser']) || _truthy(m['is_admin'])) {
      return UserRole.admin;
    }

    final rawRole = _normString(m['role']);
    if (rawRole == 'admin') return UserRole.admin;
    if (rawRole == 'station') return UserRole.station;

    final fromOdooGroupsId = _roleFromOdooGroupsId(m['groups_id']);
    if (fromOdooGroupsId != null) return fromOdooGroupsId;

    if (_truthy(m['is_acpec_admin'])) {
      return UserRole.admin;
    }

    final fromPerm =
        _roleFromStringList(m['permissions']) ??
        _roleFromStringList(m['scopes']) ??
        _roleFromStringList(m['capabilities']);
    if (fromPerm != null) return fromPerm;

    if (_adminFromStrings(m)) {
      return UserRole.admin;
    }
    if (_stationFromStrings(m)) {
      return UserRole.station;
    }

    final fromGroups =
        _roleFromGroups(m['groups']) ?? _roleFromGroups(m['group_ids']);
    if (fromGroups != null) return fromGroups;

    if (_truthy(m['is_staff']) &&
        (_truthy(m['can_manage_users']) ||
            _truthy(m['is_mobile_admin']) ||
            _truthy(m['fueltoken_admin']) ||
            _truthy(m['acpec_admin']))) {
      return UserRole.admin;
    }

    return null;
  }

  static UserRole? _roleFromStringList(dynamic g) {
    if (g is! List) return null;
    var station = false;
    var admin = false;
    for (final e in g) {
      final s = e?.toString().toLowerCase() ?? '';
      if (s.isEmpty) continue;
      if (_stationToken(s)) station = true;
      if (_adminToken(s) ||
          (s.contains('approve') && s.contains('account')) ||
          s.contains('account_request')) {
        admin = true;
      }
    }
    if (admin) return UserRole.admin;
    if (station) return UserRole.station;
    return null;
  }

  /// Odoo `res.users` : `groups_id` peut être `[[id, "Nom du groupe"], …]` ou
  /// des commandes M2M ; on extrait les libellés texte quand ils sont présents.
  static UserRole? _roleFromOdooGroupsId(dynamic g) {
    if (g is! List) return null;
    var station = false;
    var admin = false;
    for (final e in g) {
      if (e is List) {
        if (e.length >= 2 && e[1] is String) {
          final name = e[1]!.toString().toLowerCase();
          if (_stationToken(name)) station = true;
          if (_adminToken(name)) admin = true;
        } else {
          for (final part in e) {
            if (part is String) {
              final n = part.toLowerCase();
              if (_stationToken(n)) station = true;
              if (_adminToken(n)) admin = true;
            }
          }
        }
      } else {
        final s = _stringOfGroupEntry(e)?.toLowerCase() ?? '';
        if (_stationToken(s)) station = true;
        if (_adminToken(s)) admin = true;
      }
    }
    if (admin) return UserRole.admin;
    if (station) return UserRole.station;
    return null;
  }

  static UserRole? _roleFromGroups(dynamic g) {
    if (g is! List) return null;
    var station = false;
    var admin = false;
    for (final e in g) {
      final s = _stringOfGroupEntry(e);
      if (s == null) continue;
      final n = s.toLowerCase();
      if (_stationToken(n)) station = true;
      if (_adminToken(n)) admin = true;
    }
    if (admin) return UserRole.admin;
    if (station) return UserRole.station;
    return null;
  }

  static String? _stringOfGroupEntry(dynamic e) {
    if (e is String) return e;
    if (e is Map) {
      return (e['name'] ??
              e['display_name'] ??
              e['xml_id'] ??
              e['complete_name'])
          ?.toString();
    }
    return e?.toString();
  }

  static bool _adminFromStrings(Map<String, dynamic> m) {
    const keys = [
      'role',
      'user_role',
      'user_type',
      'type_utilisateur',
      'account_type',
      'partner_type',
      'kind',
      'profile_type',
      'profile',
      'access_level',
    ];
    for (final k in keys) {
      if (_adminToken(_normString(m[k]))) return true;
    }
    return false;
  }

  static bool _stationFromStrings(Map<String, dynamic> m) {
    const keys = [
      'role',
      'user_role',
      'user_type',
      'type_utilisateur',
      'partner_type',
      'kind',
      'profile_type',
      'profile',
    ];
    for (final k in keys) {
      if (_stationToken(_normString(m[k]))) return true;
    }
    return false;
  }

  static String _normString(dynamic v) =>
      (v ?? '').toString().toLowerCase().trim();

  static bool _adminToken(String n) {
    if (n.isEmpty) return false;
    return n.contains('admin') ||
        n.contains('gestion') ||
        n.contains('superuser') ||
        n.contains('backend') ||
        (n.contains('manager') && !n.contains('station'));
  }

  static bool _stationToken(String n) {
    if (n.isEmpty) return false;
    return n.contains('station') ||
        n.contains('pomp') ||
        n.contains('pump') ||
        n.contains('scanner') ||
        n == 'operator';
  }

  static bool _truthy(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final t = v.toLowerCase().trim();
      return t == 'true' || t == '1' || t == 'yes';
    }
    return false;
  }
}
