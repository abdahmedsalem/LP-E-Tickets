// Step 1 ACPEC : version-check & signup-companies.

class AcpecBootstrapException implements Exception {
  AcpecBootstrapException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Extrait le champ `data` lorsque la réponse contient `ok: true`.
Map<String, dynamic> acpecParseEnvelope(dynamic result) {
  if (result is! Map) {
    throw AcpecBootstrapException('Réponse ACPEC invalide (objet attendu).');
  }
  final map = Map<String, dynamic>.from(result);
  final ok = map['ok'];
  if (ok != true) {
    final msg = map['message']?.toString() ??
        map['error']?.toString() ??
        'Serveur ACPEC : ok != true';
    throw AcpecBootstrapException(msg);
  }
  final data = map['data'];
  if (data is! Map) {
    throw AcpecBootstrapException('Champ data manquant ou invalide.');
  }
  return Map<String, dynamic>.from(data);
}

class AcpecVersionCheckData {
  const AcpecVersionCheckData({
    required this.status,
    required this.minSupportedVersion,
    required this.latestVersion,
    required this.forceUpdate,
    required this.messageRaw,
  });

  final String status;
  final bool minSupportedVersion;
  final bool latestVersion;
  final bool forceUpdate;
  final String? messageRaw;

  factory AcpecVersionCheckData.fromDataMap(Map<String, dynamic> data) {
    return AcpecVersionCheckData(
      status: data['status']?.toString() ?? '—',
      minSupportedVersion: data['min_supported_version'] == true,
      latestVersion: data['latest_version'] == true,
      forceUpdate: data['force_update'] == true,
      messageRaw: _stringOrNull(data['message']),
    );
  }

  static String? _stringOrNull(dynamic v) {
    if (v == null || v is bool && v == false) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'false') return null;
    return s;
  }
}

class AcpecSignupCompany {
  const AcpecSignupCompany({required this.id, required this.name});

  final int id;
  final String name;

  static List<AcpecSignupCompany> listFromDataMap(Map<String, dynamic> data) {
    final raw = data['items'];
    if (raw is! List) return [];
    final out = <AcpecSignupCompany>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = m['id'];
      final name = m['name']?.toString().trim() ?? '';
      if (id is int) {
        out.add(AcpecSignupCompany(id: id, name: name.isEmpty ? '—' : name));
      } else if (id != null) {
        final parsed = int.tryParse('$id');
        if (parsed != null) {
          out.add(AcpecSignupCompany(id: parsed, name: name.isEmpty ? '—' : name));
        }
      }
    }
    return out;
  }
}
