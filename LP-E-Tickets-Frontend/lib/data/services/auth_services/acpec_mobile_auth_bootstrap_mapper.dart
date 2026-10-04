import '../../../domain/models/auth/acpec_mobile_auth_bootstrap.dart';

class AcpecMobileAuthBootstrapMapper {
  static Map<String, dynamic> parseEnvelope(dynamic result) {
    if (result is! Map) {
      throw const AcpecBootstrapFailure(
        'Réponse ACPEC invalide (objet attendu).',
      );
    }
    final map = Map<String, dynamic>.from(result);
    if (map['ok'] != true) {
      throw AcpecBootstrapFailure(
        map['message']?.toString() ??
            map['error']?.toString() ??
            'Serveur ACPEC : ok != true',
      );
    }
    final data = map['data'];
    if (data is! Map) {
      throw const AcpecBootstrapFailure('Champ data manquant ou invalide.');
    }
    return Map<String, dynamic>.from(data);
  }

  static AcpecVersionCheckData versionFromResponse(dynamic response) {
    final data = parseEnvelope(response);
    return AcpecVersionCheckData(
      status: data['status']?.toString() ?? '—',
      minSupportedVersion: data['min_supported_version'] == true,
      latestVersion: data['latest_version'] == true,
      forceUpdate: data['force_update'] == true,
      messageRaw: _stringOrNull(data['message']),
    );
  }

  static List<AcpecSignupCompany> companiesFromResponse(dynamic response) {
    final raw = parseEnvelope(response)['items'];
    if (raw is! List) return [];
    final out = <AcpecSignupCompany>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = map['id'];
      final parsedId = id is int ? id : int.tryParse('$id');
      if (parsedId == null) continue;
      final name = map['name']?.toString().trim() ?? '';
      out.add(
        AcpecSignupCompany(id: parsedId, name: name.isEmpty ? '—' : name),
      );
    }
    return out;
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null || value is bool && value == false) return null;
    final text = value.toString().trim();
    return text.isEmpty || text == 'false' ? null : text;
  }
}
