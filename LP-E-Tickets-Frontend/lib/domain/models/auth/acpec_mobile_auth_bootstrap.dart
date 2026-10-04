class AcpecBootstrapFailure implements Exception {
  const AcpecBootstrapFailure(this.message);
  final String message;
  @override
  String toString() => message;
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
}

class AcpecSignupCompany {
  const AcpecSignupCompany({required this.id, required this.name});
  final int id;
  final String name;
}

class AcpecMobileAuthBootstrap {
  const AcpecMobileAuthBootstrap({
    required this.version,
    required this.companies,
  });
  final AcpecVersionCheckData version;
  final List<AcpecSignupCompany> companies;
}
