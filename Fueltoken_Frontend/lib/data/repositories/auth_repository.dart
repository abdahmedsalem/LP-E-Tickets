import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/auth/auth_token_store.dart';
import '../../core/auth/odoo_session_store.dart';
import '../../core/config/app_brand_config.dart';
import '../../core/config/acpec_role_overrides.dart';
import '../../core/config/odoo_api_config.dart';
import '../../core/config/odoo_auth_rpc_config.dart';
import '../../core/utils/error_presenter.dart';
import '../../core/validation/contact_validators.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import '../services/odoo_auth_service.dart';

/// Doctrine: every new account is created as `user`. Admin can change role.
class AuthRepository {
  AuthRepository._();

  static final AuthRepository instance = AuthRepository._();

  final _uuid = const Uuid();
  final List<AppUser> _users = [];

  AppUser? _current;

  /// Mot de passe mock par utilisateur (inscription / reset après OTP).
  final Map<String, String> _passwordByUserId = {};

  AppUser? get currentUser => _current;

  /// Connexion Odoo ACPEC lorsque la base URL et la route login sont configurées ; sinon mode local.
  Future<AppUser> login(String identifier, String password) async {
    if (OdooApiConfig.isConfigured && OdooAuthRpcConfig.hasLogin) {
      return await _loginOdoo(identifier, password);
    }
    return _loginLocal(identifier, password);
  }

  Future<AppUser> _loginOdoo(String identifier, String password) async {
    try {
      final user = AcpecRoleOverrides.apply(
        await OdooAuthService.instance.login(
          identifier: identifier,
          password: password,
        ),
      );
      _current = user;
      return user;
    } catch (e) {
      throw Exception(ErrorPresenter.message(e));
    }
  }

  Future<AppUser> _loginLocal(String identifier, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final raw = identifier.trim();
    final normalized = raw.contains('@')
        ? raw.toLowerCase()
        : normalizePhoneIdentifierForLookup(raw);
    final user = _users.firstWhere(
      (u) =>
          u.email.toLowerCase() == normalized ||
          u.phone.replaceAll(' ', '').toLowerCase() ==
              normalized.replaceAll(' ', ''),
      orElse: () => throw Exception('Compte introuvable.'),
    );
    if (password.length < 4) {
      throw Exception('Mot de passe incorrect.');
    }
    final stored = _passwordByUserId[user.id];
    if (stored != null && stored != password) {
      throw Exception('Mot de passe incorrect.');
    }
    _current = user;
    return user;
  }

  /// Restaure la session Odoo (`session-check` avec cookie / session et/ou Bearer).
  Future<AppUser?> tryRestoreRemoteSession() async {
    if (OdooApiConfig.isConfigured && OdooAuthRpcConfig.hasSessionMe) {
      final sid = await OdooSessionStore.readSessionId();
      final bearer = await OdooSessionStore.readAccessToken();
      if ((sid == null || sid.isEmpty) && (bearer == null || bearer.isEmpty)) {
        return null;
      }
      try {
        final user = AcpecRoleOverrides.apply(
          await OdooAuthService.instance.sessionMe(),
        );
        _current = user;
        return user;
      } catch (_) {
        await OdooSessionStore.clear();
      }
    }
    return null;
  }

  Future<AppUser> register({
    required String email,
    required String name,
    required String phone,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (_users.any((u) => u.email.toLowerCase() == email.toLowerCase())) {
      throw Exception('Un compte existe déjà avec cet email.');
    }
    final user = AppUser(
      id: 'u-${_uuid.v4().substring(0, 6)}',
      email: email,
      name: name,
      phone: phone,
      role: UserRole.user, // doctrine: new accounts always = user
      companyId: AppBrandConfig.effectiveDefaultCompanyId,
      createdAt: DateTime.now(),
    );
    _users.add(user);
    _passwordByUserId[user.id] = password;
    _current = user;
    return user;
  }

  /// Compte créé côté API (`complete-registration`) — enregistre JWT + cache profil.
  Future<AppUser> adoptRemoteUser({
    required AppUser user,
    required String password,
    Map<String, dynamic>? tokens,
  }) async {
    final access = tokens?['access']?.toString() ?? '';
    final refresh = tokens?['refresh']?.toString() ?? '';
    final hasJwt = access.isNotEmpty && refresh.isNotEmpty;
    if (hasJwt) {
      await OdooSessionStore.clear();
      await AuthTokenStore.save(access: access, refresh: refresh);
    } else {
      await AuthTokenStore.clear();
      // Inscription / session Odoo : conserver session_id stockée.
    }
    await Future.delayed(const Duration(milliseconds: 100));
    if (password.length < 4) {
      throw Exception('Mot de passe trop court.');
    }
    final resolved = AcpecRoleOverrides.apply(user);
    final idxId = _users.indexWhere((u) => u.id == resolved.id);
    if (idxId >= 0) {
      _users[idxId] = resolved;
    } else {
      final idxEmail = _users.indexWhere(
        (u) => u.email.toLowerCase() == resolved.email.toLowerCase(),
      );
      if (idxEmail >= 0) {
        _users[idxEmail] = resolved;
      } else {
        _users.add(resolved);
      }
    }
    _passwordByUserId[resolved.id] = password;
    _current = resolved;
    return resolved;
  }

  /// Si l’identifiant correspond à un utilisateur seed local, aligne le mot de passe (ex. après reset OTP).
  Future<void> syncLocalPasswordIfExists({
    required String identifier,
    required String newPassword,
  }) async {
    if (newPassword.length < 4) return;
    final raw = identifier.trim();
    final normalized = raw.contains('@')
        ? raw.toLowerCase()
        : normalizePhoneIdentifierForLookup(raw);
    for (final u in _users) {
      final idMatch = u.email.toLowerCase() == normalized;
      final phoneMatch =
          u.phone.replaceAll(' ', '').toLowerCase() ==
          normalized.replaceAll(' ', '').toLowerCase();
      if (idMatch || phoneMatch) {
        _passwordByUserId[u.id] = newPassword;
        return;
      }
    }
  }

  /// Après vérification OTP (mot de passe oublié).
  Future<void> resetPasswordForIdentifier({
    required String identifier,
    required String newPassword,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (newPassword.length < 4) {
      throw Exception('Le mot de passe doit avoir au moins 4 caractères.');
    }
    final raw = identifier.trim();
    final normalized = raw.contains('@')
        ? raw.toLowerCase()
        : normalizePhoneIdentifierForLookup(raw);
    AppUser? user;
    for (final u in _users) {
      final idMatch = u.email.toLowerCase() == normalized;
      final phoneMatch =
          u.phone.replaceAll(' ', '').toLowerCase() ==
          normalized.replaceAll(' ', '').toLowerCase();
      if (idMatch || phoneMatch) {
        user = u;
        break;
      }
    }
    if (user == null) {
      throw Exception('Compte introuvable.');
    }
    _passwordByUserId[user.id] = newPassword;
  }

  Future<void> logout() async {
    _current = null;
    await AuthTokenStore.clear();
    if (OdooApiConfig.isConfigured) {
      try {
        await OdooAuthService.instance.logout().timeout(
          const Duration(seconds: 2),
        );
      } on TimeoutException {
        await OdooSessionStore.clear();
      } catch (_) {
        await OdooSessionStore.clear();
      }
    } else {
      await OdooSessionStore.clear();
    }
  }

  Future<List<AppUser>> listUsers() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_users);
  }

  /// Admin-only: change a user's role.
  Future<AppUser> changeRole(
    String userId,
    UserRole newRole, {
    String? stationId,
  }) async {
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx < 0) throw Exception('Utilisateur introuvable.');
    final updated = _users[idx].copyWith(
      role: newRole,
      stationId: newRole == UserRole.station ? stationId : null,
    );
    _users[idx] = updated;
    if (_current?.id == userId) _current = updated;
    return updated;
  }
}
