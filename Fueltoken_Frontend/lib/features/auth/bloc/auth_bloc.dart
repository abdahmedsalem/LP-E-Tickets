import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/debug/acpec_rpc_debug.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/user_role.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';

// ─────────── Events
abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

/// Au démarrage : restauration session Odoo si disponible.
class AuthHydrateRequested extends AuthEvent {
  const AuthHydrateRequested();
}

/// Rafraîchissement manuel depuis l’écran d’activation en attente.
///
/// Ne repasse pas par la logique de démarrage/PIN local :
/// - si le device reste non trusted, on reste sur l’écran d’attente ;
/// - si le device devient trusted, le router ouvre l’écran métier adapté ;
/// - si la session est expirée, retour login.
class AuthActivationRefreshRequested extends AuthEvent {
  const AuthActivationRefreshRequested();
}

class AuthLoginRequested extends AuthEvent {
  final String identifier; // email ou téléphone
  final String pin;
  const AuthLoginRequested({required this.identifier, required this.pin});
  @override
  List<Object?> get props => [identifier, pin];
}

class AuthLoginOtpRequested extends AuthEvent {
  final String identifier;

  const AuthLoginOtpRequested({required this.identifier});

  @override
  List<Object?> get props => [identifier];
}

class AuthLoginOtpVerified extends AuthEvent {
  final String identifier;
  final String code;
  final int? challengeId;

  const AuthLoginOtpVerified({
    required this.identifier,
    required this.code,
    this.challengeId,
  });

  @override
  List<Object?> get props => [identifier, code, challengeId];
}

class AuthRegisterRequested extends AuthEvent {
  final String email;
  final String name;
  final String phone;
  final String pin;
  const AuthRegisterRequested({
    required this.email,
    required this.name,
    required this.phone,
    required this.pin,
  });
  @override
  List<Object?> get props => [email, name, phone, pin];
}

/// Inscription finalisée après validation OTP (service REST externe).
class AuthRemoteRegistrationCompleted extends AuthEvent {
  final AppUser user;
  final String pin;
  final Map<String, dynamic>? tokens;
  const AuthRemoteRegistrationCompleted({
    required this.user,
    required this.pin,
    this.tokens,
  });
  @override
  List<Object?> get props => [user, pin, tokens];
}

/// Session ACPEC établie après inscription + approbation.
class AuthSessionEstablished extends AuthEvent {
  final AppUser user;
  const AuthSessionEstablished(this.user);
  @override
  List<Object?> get props => [user];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

/// Session ACPEC expirée ou révoquée : déconnexion locale + message sur l’écran de login.
class AuthSessionExpiredRequested extends AuthEvent {
  const AuthSessionExpiredRequested();
}

class AuthUnlockRequested extends AuthEvent {
  final String pin;
  const AuthUnlockRequested({required this.pin});
  @override
  List<Object?> get props => [pin];
}

enum AuthLockReason { appLifecycle, idleTimeout, manual }

class AuthLockRequested extends AuthEvent {
  final AuthLockReason reason;
  const AuthLockRequested({required this.reason});
  @override
  List<Object?> get props => [reason];
}

class AuthRoleChanged extends AuthEvent {
  final UserRole role;
  final String? stationId;
  final String userId;
  const AuthRoleChanged({
    required this.userId,
    required this.role,
    this.stationId,
  });
  @override
  List<Object?> get props => [userId, role, stationId];
}

// ─────────── State
enum AuthStatus {
  unknown,
  unauthenticated,
  authenticating,
  authenticated,
  locked,
  failure,
}

class AuthState extends Equatable {
  final AuthStatus status;
  final AppUser? user;
  final String? errorMessage;

  /// Affiché sur l’écran de connexion après expiration de session (non technique).
  final String? loginInfoMessage;

  /// Challenge OTP courant pour le login mobile ACPEC.
  final int? loginOtpChallengeId;
  final String? loginOtpIdentifier;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.errorMessage,
    this.loginInfoMessage,
    this.loginOtpChallengeId,
    this.loginOtpIdentifier,
  });

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    String? errorMessage,
    String? loginInfoMessage,
    int? loginOtpChallengeId,
    String? loginOtpIdentifier,
    bool clearError = false,
    bool clearLoginInfo = false,
    bool clearLoginOtp = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loginInfoMessage: clearLoginInfo
          ? null
          : (loginInfoMessage ?? this.loginInfoMessage),
      loginOtpChallengeId: clearLoginOtp
          ? null
          : (loginOtpChallengeId ?? this.loginOtpChallengeId),
      loginOtpIdentifier: clearLoginOtp
          ? null
          : (loginOtpIdentifier ?? this.loginOtpIdentifier),
    );
  }

  @override
  List<Object?> get props => [
    status,
    user,
    errorMessage,
    loginInfoMessage,
    loginOtpChallengeId,
    loginOtpIdentifier,
  ];
}

// ─────────── Bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repo;

  static const String _pinResetRequiredMessage =
      'PIN à réinitialiser. Utilisez PIN oublié pour sécuriser votre accès.';

  AuthBloc({AuthRepository? repo})
    : _repo = repo ?? AuthRepository.instance,
      super(const AuthState(status: AuthStatus.unauthenticated)) {
    on<AuthHydrateRequested>(_onHydrate);
    on<AuthActivationRefreshRequested>(_onActivationRefresh);
    on<AuthLoginRequested>(_onLogin);
    on<AuthLoginOtpRequested>(_onLoginOtpRequested);
    on<AuthLoginOtpVerified>(_onLoginOtpVerified);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthRemoteRegistrationCompleted>(_onRemoteRegistrationCompleted);
    on<AuthSessionEstablished>(_onSessionEstablished);
    on<AuthLogoutRequested>(_onLogout);
    on<AuthSessionExpiredRequested>(_onSessionExpired);
    on<AuthUnlockRequested>(_onUnlock);
    on<AuthLockRequested>(_onLockRequested);
    on<AuthRoleChanged>(_onRoleChanged);
  }

  Future<void> _onHydrate(
    AuthHydrateRequested e,
    Emitter<AuthState> emit,
  ) async {
    final user = await _repo.tryRestoreRemoteSession();
    if (user == null) return;

    // Patch33B : une session Bearer restaurée prouve l'identité technique,
    // mais n'ouvre plus l'application sans confirmation PIN serveur.
    emit(AuthState(status: AuthStatus.locked, user: user));
  }

  Future<void> _onActivationRefresh(
    AuthActivationRefreshRequested e,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(
        status: AuthStatus.authenticating,
        clearError: true,
        clearLoginInfo: true,
      ),
    );
    try {
      final user = await _repo.tryRestoreRemoteSession();
      if (user == null) {
        emit(
          const AuthState(
            status: AuthStatus.unauthenticated,
            loginInfoMessage:
                'Votre session a expiré. Reconnectez-vous pour continuer.',
          ),
        );
        return;
      }
      emit(AuthState(status: AuthStatus.locked, user: user));
    } catch (err) {
      emit(
        state.copyWith(
          status: AuthStatus.authenticated,
          errorMessage: ErrorPresenter.message(err),
        ),
      );
    }
  }

  Future<void> _onSessionExpired(
    AuthSessionExpiredRequested e,
    Emitter<AuthState> emit,
  ) async {
    emit(
      const AuthState(
        status: AuthStatus.unauthenticated,
        loginInfoMessage:
            'Pour des raisons de sécurité, votre session s’est terminée. '
            'Reconnectez-vous pour continuer.',
      ),
    );
    try {
      await _repo.logout();
    } catch (_) {}
  }

  Future<void> _onLogin(AuthLoginRequested e, Emitter<AuthState> emit) async {
    emit(
      state.copyWith(
        status: AuthStatus.authenticating,
        clearError: true,
        clearLoginInfo: true,
      ),
    );
    if (AcpecRpcDebug.enabled) {
      final id = e.identifier.trim();
      developer.log(
        'AuthLogin identifierKind=${id.contains('@') ? 'email' : 'phone'} '
        'identifierLen=${id.length} secretCodeLen=${e.pin.length}',
        name: 'ACPEC_AUTH',
      );
    }
    try {
      final user = await _repo.login(e.identifier, e.pin);
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } catch (err) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: ErrorPresenter.message(err),
        ),
      );
    }
  }

  Future<void> _onLoginOtpRequested(
    AuthLoginOtpRequested e,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(
        status: AuthStatus.authenticating,
        clearError: true,
        clearLoginInfo: true,
        clearLoginOtp: true,
      ),
    );
    if (AcpecRpcDebug.enabled) {
      final id = e.identifier.trim();
      developer.log(
        'AuthLoginOtp request identifierKind=${id.contains('@') ? 'email' : 'phone'} '
        'identifierLen=${id.length}',
        name: 'ACPEC_AUTH',
      );
    }
    try {
      final body = await _repo.requestLoginOtp(identifier: e.identifier);
      final data = body['data'];
      int? challengeId;
      if (data is Map) {
        final raw = data['challenge_id'] ?? data['otp_challenge_id'];
        challengeId = int.tryParse(raw?.toString() ?? '');
      }
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          loginOtpChallengeId: challengeId,
          loginOtpIdentifier: e.identifier,
        ),
      );
    } catch (err) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: ErrorPresenter.message(err),
        ),
      );
    }
  }

  Future<void> _onLoginOtpVerified(
    AuthLoginOtpVerified e,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(
        status: AuthStatus.authenticating,
        clearError: true,
        clearLoginInfo: true,
      ),
    );
    if (AcpecRpcDebug.enabled) {
      final id = e.identifier.trim();
      developer.log(
        'AuthLoginOtp verify identifierKind=${id.contains('@') ? 'email' : 'phone'} '
        'identifierLen=${id.length} codeLen=${e.code.length}',
        name: 'ACPEC_AUTH',
      );
    }
    try {
      final user = await _repo.verifyLoginOtp(
        identifier: e.identifier,
        code: e.code,
        challengeId: e.challengeId,
      );
      // OTP login établit la session serveur. Le PIN local n'est plus requis
      // ni synchronisé : aux prochaines ouvertures, confirm-pin serveur
      // déverrouillera l'application.
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } catch (err) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: ErrorPresenter.message(err),
        ),
      );
    }
  }

  Future<void> _onRegister(
    AuthRegisterRequested e,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(
        status: AuthStatus.authenticating,
        clearError: true,
        clearLoginInfo: true,
      ),
    );
    try {
      final user = await _repo.register(
        email: e.email,
        name: e.name,
        phone: e.phone,
        pin: e.pin,
      );
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } catch (err) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: ErrorPresenter.message(err),
        ),
      );
    }
  }

  Future<void> _onRemoteRegistrationCompleted(
    AuthRemoteRegistrationCompleted e,
    Emitter<AuthState> emit,
  ) async {
    emit(
      state.copyWith(
        status: AuthStatus.authenticating,
        clearError: true,
        clearLoginInfo: true,
      ),
    );
    try {
      final user = await _repo.adoptRemoteUser(
        user: e.user,
        pin: e.pin,
        tokens: e.tokens,
      );
      // Le PIN fourni à l'inscription est créé côté serveur. Ne pas
      // l'enregistrer comme PIN local d'ouverture.
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } catch (err) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: ErrorPresenter.message(err),
        ),
      );
    }
  }

  Future<void> _onSessionEstablished(
    AuthSessionEstablished e,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthState(status: AuthStatus.authenticated, user: e.user));
  }

  Future<void> _onLogout(AuthLogoutRequested e, Emitter<AuthState> emit) async {
    emit(const AuthState(status: AuthStatus.unauthenticated));
    try {
      await _repo.logout();
    } catch (_) {
      // État déjà « déconnecté » ; le dépôt vide en principe les jetons localement.
    }
  }

  Future<void> _onLockRequested(
    AuthLockRequested e,
    Emitter<AuthState> emit,
  ) async {
    if (state.status != AuthStatus.authenticated || state.user == null) {
      return;
    }
    emit(
      state.copyWith(
        status: AuthStatus.locked,
        clearError: true,
        clearLoginInfo: true,
      ),
    );
  }

  Future<void> _onUnlock(AuthUnlockRequested e, Emitter<AuthState> emit) async {
    final lockedUser = state.user;
    emit(
      state.copyWith(
        status: AuthStatus.locked,
        user: lockedUser,
        clearError: true,
        clearLoginInfo: true,
      ),
    );
    try {
      final user = await _repo.confirmOpenPin(e.pin);
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } catch (err) {
      if (_serverPinRequiresLogin(err)) {
        emit(
          const AuthState(
            status: AuthStatus.unauthenticated,
            loginInfoMessage:
                'Votre session a expiré. Reconnectez-vous pour continuer.',
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          status: AuthStatus.locked,
          user: lockedUser,
          errorMessage: _serverPinErrorMessage(err),
        ),
      );
    }
  }

  bool _serverPinRequiresLogin(Object err) {
    if (err is OdooJsonRpcException) {
      return err.requiresReLogin;
    }
    return false;
  }

  String _serverPinErrorMessage(Object err) {
    if (err is OdooJsonRpcException) {
      switch (err.normalizedPublicCode) {
        case 'INVALID_ACTION_CODE':
          return 'PIN incorrect.';
        case 'ACTION_CODE_LOCKED':
          return 'Trop de tentatives. Réessayez plus tard.';
        case 'PIN_RESET_REQUIRED':
          return _pinResetRequiredMessage;
        case 'DEVICE_PENDING_TRUST':
          return 'Cet appareil est en attente de validation.';
        case 'DEVICE_BLOCKED':
          return 'Cet appareil est bloqué. Contactez l’administrateur.';
        case 'MISSING_ACTION_CODE':
          return 'PIN requis pour continuer.';
        case 'INVALID_ACTION_CODE_KEY':
          return 'Demande invalide. Veuillez réessayer.';
      }
    }
    if (ErrorPresenter.isBackendUnavailable(err)) {
      return 'Impossible de vérifier le PIN. Réessayez.';
    }
    return ErrorPresenter.message(err);
  }

  Future<void> _onRoleChanged(
    AuthRoleChanged e,
    Emitter<AuthState> emit,
  ) async {
    try {
      final updated = await _repo.changeRole(
        e.userId,
        e.role,
        stationId: e.stationId,
      );
      if (state.user?.id == updated.id) {
        emit(state.copyWith(user: updated));
      }
    } catch (_) {
      /* swallow — admin screen handles errors */
    }
  }
}
