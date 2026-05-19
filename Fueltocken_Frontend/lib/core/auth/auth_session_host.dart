/// Point d’accès minimal pour signaler une fin de session ACPEC hors des widgets
/// (ex. après échec JSON-RPC / wallet). Branché depuis [FuelTokenApp] vers [AuthBloc].
class AuthSessionHost {
  AuthSessionHost._();

  static final AuthSessionHost instance = AuthSessionHost._();

  void Function()? _onExpired;

  void attach(void Function() onExpired) => _onExpired = onExpired;

  void detach() => _onExpired = null;

  void notifySessionExpired() => _onExpired?.call();
}
