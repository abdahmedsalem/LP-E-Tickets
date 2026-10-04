import '../../../domain/models/app_user.dart';
import '../../../domain/models/user_role.dart';

/// Applies configured ACPEC roles when the backend profile has no role data.
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
        .map((email) => email.trim().toLowerCase())
        .where((email) => email.isNotEmpty)
        .toSet();
  }

  static bool isAcpecPrimaryAccount(String identifier) {
    final id = identifier.trim().toLowerCase();
    if (!id.contains('@')) return false;
    return _adminEmails.contains(id) || _stationEmails.contains(id);
  }

  static AppUser apply(AppUser user) {
    final email = user.email.trim().toLowerCase();
    if (_adminEmails.contains(email)) {
      return user.copyWith(role: UserRole.admin);
    }
    if (_stationEmails.contains(email)) {
      return user.copyWith(role: UserRole.station);
    }
    return user;
  }
}
