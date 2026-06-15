import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/debug/acpec_rpc_debug.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/user_role.dart';
import '../../../data/repositories/auth_repository.dart';

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

class AuthLoginRequested extends AuthEvent {
  final String identifier; // email ou téléphone
  final String password;
  const AuthLoginRequested({required this.identifier, required this.password});
  @override
  List<Object?> get props => [identifier, password];
}

class AuthRegisterRequested extends AuthEvent {
  final String email;
  final String name;
  final String phone;
  final String password;
  const AuthRegisterRequested({
    required this.email,
    required this.name,
    required this.phone,
    required this.password,
  });
  @override
  List<Object?> get props => [email, name, phone, password];
}

/// Inscription finalisée après validation OTP (service REST externe).
class AuthRemoteRegistrationCompleted extends AuthEvent {
  final AppUser user;
  final String password;
  final Map<String, dynamic>? tokens;
  const AuthRemoteRegistrationCompleted({
    required this.user,
    required this.password,
    this.tokens,
  });
  @override
  List<Object?> get props => [user, password];
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
  failure,
}

class AuthState extends Equatable {
  final AuthStatus status;
  final AppUser? user;
  final String? errorMessage;

  /// Affiché sur l’écran de connexion après expiration de session (non technique).
  final String? loginInfoMessage;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.errorMessage,
    this.loginInfoMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    String? errorMessage,
    String? loginInfoMessage,
    bool clearError = false,
    bool clearLoginInfo = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loginInfoMessage: clearLoginInfo
          ? null
          : (loginInfoMessage ?? this.loginInfoMessage),
    );
  }

  @override
  List<Object?> get props => [status, user, errorMessage, loginInfoMessage];
}

// ─────────── Bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repo;

  AuthBloc({AuthRepository? repo})
    : _repo = repo ?? AuthRepository.instance,
      super(const AuthState(status: AuthStatus.unauthenticated)) {
    on<AuthHydrateRequested>(_onHydrate);
    on<AuthLoginRequested>(_onLogin);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthRemoteRegistrationCompleted>(_onRemoteRegistrationCompleted);
    on<AuthSessionEstablished>(_onSessionEstablished);
    on<AuthLogoutRequested>(_onLogout);
    on<AuthSessionExpiredRequested>(_onSessionExpired);
    on<AuthRoleChanged>(_onRoleChanged);
  }

  Future<void> _onHydrate(
    AuthHydrateRequested e,
    Emitter<AuthState> emit,
  ) async {
    final user = await _repo.tryRestoreRemoteSession();
    if (user != null) {
      emit(AuthState(status: AuthStatus.authenticated, user: user));
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
        'AuthLogin identifier="$id" isEmail=${id.contains('@')} '
        'secretCodeLen=${e.password.length}',
        name: 'ACPEC_AUTH',
      );
    }
    try {
      final user = await _repo.login(e.identifier, e.password);
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
        password: e.password,
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
        password: e.password,
        tokens: e.tokens,
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
