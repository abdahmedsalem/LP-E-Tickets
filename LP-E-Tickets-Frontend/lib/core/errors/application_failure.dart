/// Stable error contract consumed by presentation code.
abstract interface class ApplicationFailure implements Exception {
  String get message;
  int? get code;
  String? get publicCode;
  String? get reference;
  bool get requiresReLogin;
  bool get requiresLogout;
  bool get isSessionExpired;
}
