import '../../../domain/models/station/station_profile.dart';

/// Maps the station profile RPC response to the domain profile.
class AcpecStationProfileMapper {
  AcpecStationProfileMapper._();

  static StationProfile fromRpc(dynamic raw) {
    if (raw is! Map) {
      throw Exception('Réponse station/profile invalide.');
    }
    var m = Map<String, dynamic>.from(raw);
    if (m['ok'] == false) {
      throw Exception(
        m['message']?.toString() ?? 'Profil station indisponible.',
      );
    }
    final d = m['data'];
    if (d is Map) {
      final dm = Map<String, dynamic>.from(d);
      if (dm['ok'] == false) {
        throw Exception(
          dm['message']?.toString() ?? 'Profil station indisponible.',
        );
      }
      m = dm;
    }

    final station =
        _pickMap(m, const ['station', 'station_profile', 'fuel_station']) ??
        _stationLikeMap(m);
    final user =
        _pickMap(m, const [
          'user',
          'mobile_user',
          'operator',
          'partner',
          'station_user',
        ]) ??
        _userLikeMap(m);

    final sid =
        _stringFrom(station, const ['id', 'station_id', 'stationId']) ?? '';
    final sname =
        _stringFrom(station, const [
          'station_name',
          'name',
          'display_name',
          'register_name',
          'pos_name',
        ]) ??
        'Station';
    final scode =
        _stringFrom(station, const [
          'station_code',
          'code',
          'ref',
          'reference',
          'station_ref',
        ]) ??
        '';
    final saddr = _addressFrom(station);
    final sactive = _boolFrom(station, const [
      'active',
      'station_active',
      'is_active',
    ], defaultValue: true);

    final oid =
        _stringFrom(user, const [
          'id',
          'user_id',
          'operator_id',
          'partner_id',
        ]) ??
        '';
    final oname =
        _stringFrom(user, const [
          'operator_name',
          'user_name',
          'name',
          'display_name',
          'full_name',
          'login',
        ]) ??
        '—';
    final oemail = _stringFrom(user, const ['email', 'login']) ?? '';
    final ophone = _stringFrom(user, const ['phone', 'mobile', 'tel']) ?? '';

    return StationProfile(
      stationId: sid.isEmpty ? '—' : sid,
      stationName: sname,
      stationCode: scode.isEmpty ? '—' : scode,
      stationAddress: saddr.isEmpty ? '—' : saddr,
      stationActive: sactive,
      operatorName: oname,
      operatorEmail: oemail,
      operatorPhone: ophone,
      operatorId: oid.isEmpty ? '—' : oid,
    );
  }

  static Map<String, dynamic>? _pickMap(
    Map<String, dynamic> m,
    List<String> keys,
  ) {
    for (final k in keys) {
      final v = m[k];
      if (v is Map) return Map<String, dynamic>.from(v);
    }
    return null;
  }

  static Map<String, dynamic>? _stationLikeMap(Map<String, dynamic> m) {
    const stationKeys = [
      'station_id',
      'station_name',
      'station_code',
      'station_ref',
      'station_address',
      'code',
      'ref',
      'reference',
    ];
    if (stationKeys.any(m.containsKey)) return m;

    final register = _pickMap(m, const ['register', 'pos_register']);
    if (register != null) return register;

    final pos = _pickMap(m, const ['pos', 'pos_config', 'config']);
    if (pos != null) return pos;

    return null;
  }

  static Map<String, dynamic>? _userLikeMap(Map<String, dynamic> m) {
    const userKeys = [
      'user_id',
      'operator_id',
      'partner_id',
      'operator_name',
      'user_name',
      'name',
      'display_name',
      'login',
      'email',
      'phone',
      'mobile',
    ];
    return userKeys.any(m.containsKey) ? m : null;
  }

  static String? _stringFrom(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return null;
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is List && v.isNotEmpty) {
        if (k.contains('id') || k == 'partner_id') {
          final s = v[0]?.toString().trim();
          if (s != null && s.isNotEmpty) return s;
        }
        if (v.length > 1 && v[1] != null) {
          final s = v[1].toString().trim();
          if (s.isNotEmpty) return s;
        }
        continue;
      }
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static String _addressFrom(Map<String, dynamic>? m) {
    if (m == null) return '';
    final direct = m['address']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final parts = <String>[];
    void add(dynamic v) {
      final s = v?.toString().trim();
      if (s != null && s.isNotEmpty) parts.add(s);
    }

    add(m['street']);
    add(m['street2']);
    add(m['city']);
    add(m['zip']);
    return parts.join(', ');
  }

  static bool _boolFrom(
    Map<String, dynamic>? m,
    List<String> keys, {
    required bool defaultValue,
  }) {
    if (m == null) return defaultValue;
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return defaultValue;
  }
}
