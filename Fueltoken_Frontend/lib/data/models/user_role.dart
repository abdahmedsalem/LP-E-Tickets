enum UserRole { user, admin, station }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.user:
        return 'Utilisateur';
      case UserRole.admin:
        return 'Administrateur';
      case UserRole.station:
        return 'Station';
    }
  }

  String get code => name;

  static UserRole fromCode(String code) {
    return UserRole.values.firstWhere(
      (r) => r.name == code,
      orElse: () => UserRole.user,
    );
  }
}
