import '../models/station.dart';

/// Mappe la réponse JSON-RPC de la liste des stations admin vers [Station].
class AcpecStationsMapper {
  AcpecStationsMapper._();

  static List<Station> fromRpcResult(
    dynamic raw, {
    required String defaultCompanyId,
  }) {
    if (raw is List) {
      return _mapFromItems(raw, defaultCompanyId: defaultCompanyId);
    }
    if (raw is! Map) {
      throw Exception('Réponse liste des stations invalide.');
    }
    final top = Map<String, dynamic>.from(raw);
    if (top['ok'] == false) {
      throw Exception(
        top['message']?.toString() ?? 'Liste des stations indisponible.',
      );
    }

    final d = top['data'];
    if (d is List) {
      return _mapFromItems(d, defaultCompanyId: defaultCompanyId);
    }

    Map<String, dynamic> data = top;
    if (d is Map) {
      data = Map<String, dynamic>.from(d);
      if (data['ok'] == false) {
        throw Exception(
          data['message']?.toString() ?? 'Liste des stations indisponible.',
        );
      }
    }

    var items = _itemsList(data);
    if (items.isEmpty) items = _itemsList(top);
    return _mapFromItems(items, defaultCompanyId: defaultCompanyId);
  }

  static List<dynamic> _itemsList(Map<String, dynamic> data) {
    for (final key in ['items', 'stations', 'records', 'results', 'rows']) {
      final v = data[key];
      if (v is List) return v;
    }
    return const [];
  }

  static List<Station> _mapFromItems(
    List<dynamic> items, {
    required String defaultCompanyId,
  }) {
    final out = <Station>[];
    for (final e in items) {
      if (e is! Map) continue;
      final row = Map<String, dynamic>.from(e);
      final s = _mapStation(row, defaultCompanyId: defaultCompanyId);
      if (s != null) out.add(s);
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static Station? _mapStation(
    Map<String, dynamic> row, {
    required String defaultCompanyId,
  }) {
    final idRaw = row['id'] ?? row['station_id'];
    if (idRaw == null) return null;
    final id = idRaw.toString().trim();
    if (id.isEmpty || id == '0') return null;

    final code =
        (row['code'] ??
                row['ref'] ??
                row['reference'] ??
                row['internal_ref'] ??
                id)
            .toString()
            .trim();
    final name =
        (row['name'] ??
                row['station_name'] ??
                row['display_name'] ??
                'Station $id')
            .toString()
            .trim();

    var address = _addressFromRow(row);
    if (address.isEmpty) address = '—';

    var companyId = defaultCompanyId;
    final co = row['company_id'];
    if (co is List && co.isNotEmpty) {
      final s = co[0]?.toString().trim();
      if (s != null && s.isNotEmpty) companyId = s;
    } else {
      final s = row['company_id']?.toString().trim();
      if (s != null && s.isNotEmpty) companyId = s;
    }

    final active =
        row['active'] != false &&
        row['active'] != 0 &&
        row['state']?.toString().toLowerCase() != 'inactive' &&
        row['state']?.toString().toLowerCase() != 'disabled';

    return Station(
      id: id,
      code: code.isEmpty ? id : code,
      name: name.isEmpty ? 'Station $id' : name,
      address: address,
      companyId: companyId,
      active: active,
    );
  }

  static String _addressFromRow(Map<String, dynamic> row) {
    final direct = row['address']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final parts = <String>[];
    void add(dynamic v) {
      final s = v?.toString().trim();
      if (s != null && s.isNotEmpty) parts.add(s);
    }

    add(row['street']);
    add(row['street2']);
    add(row['city']);
    add(row['zip']);
    final country = row['country_id'];
    if (country is List && country.length > 1) {
      add(country[1]);
    } else {
      add(row['country']);
    }

    return parts.join(', ');
  }
}
