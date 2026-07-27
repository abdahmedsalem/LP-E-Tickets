import '../../data/models/app_user.dart';
import '../../data/models/user_role.dart';

/// Rôles forcés par e-mail lorsque la réponse ACPEC/Odoo n’expose pas `role` / groupes.
///
/// Définir au build :
/// `--dart-define=ACPEC_ADMIN_EMAILS=admin01@acpec-sarl.com,autre@exemple.mr`
/// `--dart-define=ACPEC_STATION_EMAILS=station@exemple.mr`
class AcpecRoleOverrides {
  AcpecRoleOverrides._();

  static const String _adminRaw = String.fromEnvironment(
    'ACPEC_ADMIN_EMAILS',
    defaultValue: '',
  );
  static const String _stationRaw = String.fromEnvironment(
    'ACPEC_STATION_EMAILS',
    defaultValue: '',
  );

  static Set<String> get _adminEmails => _splitEmails(_adminRaw);
  static Set<String> get _stationEmails => _splitEmails(_stationRaw);

  static Set<String> _splitEmails(String raw) {
    if (raw.trim().isEmpty) return {};
    return raw
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  /// E-mail listé dans [ACPEC_ADMIN_EMAILS] ou [ACPEC_STATION_EMAILS] : l’auth ERP est la source
  /// de vérité pour ces comptes.
  static bool isAcpecPrimaryAccount(String identifier) {
    final id = identifier.trim().toLowerCase();
    if (!id.contains('@')) return false;
    return _adminEmails.contains(id) || _stationEmails.contains(id);
  }

  static AppUser apply(AppUser user) {
    final em = user.email.trim().toLowerCase();
    if (_adminEmails.contains(em)) {
      return user.copyWith(role: UserRole.admin);
    }
    if (_stationEmails.contains(em)) {
      return user.copyWith(role: UserRole.station);
    }
    return user;
  }
}
