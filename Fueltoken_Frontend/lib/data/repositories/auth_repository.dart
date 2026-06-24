import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/auth/auth_token_store.dart';
import '../../core/auth/login_session_cache.dart';
import '../../core/auth/odoo_session_store.dart';
import '../../core/config/app_brand_config.dart';
import '../../core/config/acpec_role_overrides.dart';
import '../../core/config/odoo_api_config.dart';
import '../../core/config/odoo_auth_rpc_config.dart';
import '../../core/utils/error_presenter.dart';
import '../../core/validation/contact_validators.dart';
import '../../core/validation/password_validators.dart';
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

  /// PIN mock par utilisateur (inscription / reset après OTP).
  final Map<String, String> _pinByUserId = {};

  AppUser? get currentUser => _current;

  bool _isUsableIdentifier(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    return lower != 'false' && lower != 'null';
  }

  String _cacheIdentifier(String raw) {
    final t = raw.trim();
    if (!_isUsableIdentifier(t)) return '';
    if (t.contains('@')) return t.toLowerCase();

    // Doctrine Mauritanie UI/cache : l'utilisateur manipule toujours 8 chiffres.
    // Aucun préfixe +222 n'est utilisé pour le login mobile FuelToken.
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8) return digits;
    if (digits.length == 11 && digits.startsWith('222')) {
      return digits.substring(3);
    }

    final normalized = normalizePhoneIdentifierForLookup(t);
    final normalizedDigits = normalized.replaceAll(RegExp(r'\D'), '');
    if (normalizedDigits.length == 8) return normalizedDigits;
    if (normalizedDigits.length == 11 && normalizedDigits.startsWith('222')) {
      return normalizedDigits.substring(3);
    }

    return normalized;
  }

  String _cacheIdentifierForUser(AppUser user) {
    final phone = user.phone.trim();
    if (!_isUsableIdentifier(phone)) return '';

    final localDigits = localMrDigitsFromFull(phone);
    if (kMrLocalPhoneDigits.hasMatch(localDigits)) {
      return localDigits;
    }

    final cached = _cacheIdentifier(phone);
    if (kMrLocalPhoneDigits.hasMatch(cached)) {
      return cached;
    }

    return '';
  }

  Future<bool> hasLocalUnlockPin({String? identifier}) async {
    final pin = await LoginSessionCache.lastPin();
    if (pin == null || pin.isEmpty) return false;
    final storedIdentifier = await LoginSessionCache.lastIdentifier();
    if (storedIdentifier == null || storedIdentifier.trim().isEmpty) {
      return false;
    }
    var expected = identifier != null
        ? _cacheIdentifier(identifier)
        : (_current == null ? null : _cacheIdentifierForUser(_current!));
    if (expected == null || expected.isEmpty) {
      expected = _cacheIdentifier(storedIdentifier);
    }
    if (expected.isEmpty) return false;
    return _cacheIdentifier(storedIdentifier) == expected;
  }

  Future<void> saveLocalUnlockPinForCurrentUser(String pin) async {
    final user = _current;
    if (user == null) {
      throw Exception('Session absente. Reconnectez-vous.');
    }
    if (pin.length != kSecretCodeLength) {
      throw Exception('Le PIN doit avoir 4 chiffres.');
    }
    final identifier = _cacheIdentifierForUser(user);
    await LoginSessionCache.saveLastPin(identifier: identifier, pin: pin);
    _pinByUserId[user.id] = pin;
  }

  Future<AppUser> unlockWithLocalPin(String pin) async {
    final user = _current;
    if (user == null) {
      throw Exception('Session absente. Reconnectez-vous.');
    }
    if (pin.length != kSecretCodeLength) {
      throw Exception('PIN incorrect.');
    }
    final hasPinForUser = await hasLocalUnlockPin();
    final storedPin = await LoginSessionCache.lastPin();
    if (!hasPinForUser || storedPin != pin.trim()) {
      throw Exception('PIN incorrect.');
    }
    return user;
  }

  /// Connexion Odoo ACPEC lorsque la base URL et la route login sont configurées ; sinon mode local.
  Future<AppUser> login(String identifier, String pin) async {
    if (OdooApiConfig.isConfigured && OdooAuthRpcConfig.hasLogin) {
      return await _loginOdoo(identifier, pin);
    }
    return _loginLocal(identifier, pin);
  }

  Future<AppUser> _loginOdoo(String identifier, String pin) async {
    try {
      final user = AcpecRoleOverrides.apply(
        await OdooAuthService.instance.login(identifier: identifier, pin: pin),
      );
      _current = user;
      final cachedIdentifier = _cacheIdentifierForUser(user);
      if (cachedIdentifier.isNotEmpty) {
        await LoginSessionCache.saveLastIdentifier(cachedIdentifier);
      }
      return user;
    } catch (e) {
      throw Exception(ErrorPresenter.message(e));
    }
  }

  Future<AppUser> _loginLocal(String identifier, String pin) async {
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
    if (pin.length != kSecretCodeLength) {
      throw Exception('PIN incorrect.');
    }
    final stored = _pinByUserId[user.id];
    if (stored != null && stored != pin) {
      throw Exception('PIN incorrect.');
    }
    _current = user;
    return user;
  }

  /// Restaure la session Odoo (`session-check` avec cookie / session et/ou Bearer).
  ///
  /// Doctrine session longue : un access token expiré ne doit pas provoquer un
  /// retour immédiat au login. Si un refresh token est disponible, on tente
  /// d'abord `/refresh`, puis un nouveau `session-check`. Les jetons ne sont
  /// effacés que si le refresh échoue réellement.
  Future<AppUser?> tryRestoreRemoteSession() async {
    if (OdooApiConfig.isConfigured && OdooAuthRpcConfig.hasSessionMe) {
      final sid = await OdooSessionStore.readSessionId();
      final bearer = await OdooSessionStore.readAccessToken();
      final refresh = await OdooSessionStore.readRefreshToken();
      final hasSession = sid != null && sid.isNotEmpty;
      final hasBearer = bearer != null && bearer.isNotEmpty;
      final hasRefresh = refresh != null && refresh.isNotEmpty;
      if (!hasSession && !hasBearer && !hasRefresh) {
        return null;
      }

      if (hasSession || hasBearer) {
        try {
          final user = AcpecRoleOverrides.apply(
            await OdooAuthService.instance.sessionMe(),
          );
          _current = user;
          return user;
        } catch (_) {
          // Access token expiré ou session courte refusée : ne pas purger ici.
          // La session longue doit encore pouvoir être renouvelée.
        }
      }

      if (hasRefresh) {
        try {
          final refreshed = AcpecRoleOverrides.apply(
            await OdooAuthService.instance.refreshSession(
              refreshToken: refresh,
            ),
          );
          _current = refreshed;
          return refreshed;
        } catch (_) {
          await OdooSessionStore.clear();
          await AuthTokenStore.clear();
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> requestLoginOtp({
    required String identifier,
  }) async {
    if (!OdooApiConfig.isConfigured ||
        OdooAuthRpcConfig.requestOtpRoute.isEmpty) {
      throw Exception('Connexion OTP ACPEC indisponible.');
    }
    try {
      return await OdooAuthService.instance.requestLoginOtp(
        identifier: identifier,
      );
    } catch (e) {
      throw Exception(ErrorPresenter.message(e));
    }
  }

  Future<AppUser> verifyLoginOtp({
    required String identifier,
    required String code,
    int? challengeId,
  }) async {
    if (!OdooApiConfig.isConfigured ||
        OdooAuthRpcConfig.verifyOtpRoute.isEmpty) {
      throw Exception('Vérification OTP ACPEC indisponible.');
    }
    try {
      final user = AcpecRoleOverrides.apply(
        await OdooAuthService.instance.verifyLoginOtp(
          identifier: identifier,
          code: code,
          challengeId: challengeId,
        ),
      );
      final idx = _users.indexWhere((u) => u.id == user.id);
      if (idx >= 0) {
        _users[idx] = user;
      } else {
        _users.add(user);
      }
      _current = user;
      final cachedIdentifier = _cacheIdentifierForUser(user);
      if (cachedIdentifier.isNotEmpty) {
        await LoginSessionCache.saveLastIdentifier(cachedIdentifier);
      }
      return user;
    } catch (e) {
      throw Exception(ErrorPresenter.message(e));
    }
  }

  Future<AppUser> register({
    required String email,
    required String name,
    required String phone,
    required String pin,
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
    _pinByUserId[user.id] = pin;
    await LoginSessionCache.saveLastPin(
      identifier: _cacheIdentifier(phone),
      pin: pin,
    );
    _current = user;
    return user;
  }

  /// Compte créé côté API (`complete-registration`) — enregistre JWT + cache profil.
  Future<AppUser> adoptRemoteUser({
    required AppUser user,
    required String pin,
    Map<String, dynamic>? tokens,
  }) async {
    final access = tokens?['access']?.toString().trim() ?? '';
    final refresh = tokens?['refresh']?.toString().trim() ?? '';
    final hasJwt = access.isNotEmpty && refresh.isNotEmpty;
    if (!hasJwt) {
      await AuthTokenStore.clear();
      throw Exception(
        'Compte créé. Activation en attente par le back-office. '
        'Connectez-vous après approbation.',
      );
    }

    // Session mobile ACPEC/Odoo : les tokens retournés par verify-otp doivent
    // rester dans OdooSessionStore, car c'est ce store que la restauration au
    // démarrage lit après F5 / réouverture de l'application.
    await OdooSessionStore.saveAccessToken(access);
    await OdooSessionStore.saveRefreshToken(refresh);
    await AuthTokenStore.clear();
    await Future.delayed(const Duration(milliseconds: 100));
    if (pin.length != kSecretCodeLength) {
      throw Exception('Le PIN doit avoir 4 chiffres.');
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
    _pinByUserId[resolved.id] = pin;
    await LoginSessionCache.saveLastPin(
      identifier: _cacheIdentifierForUser(resolved),
      pin: pin,
    );
    _current = resolved;
    return resolved;
  }

  /// Si l’identifiant correspond à un utilisateur seed local, aligne le PIN (ex. après reset OTP).
  Future<void> syncLocalPinIfExists({
    required String identifier,
    required String newPin,
  }) async {
    if (newPin.length != kSecretCodeLength) return;
    await LoginSessionCache.saveLastPin(
      identifier: _cacheIdentifier(identifier),
      pin: newPin,
    );
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
        _pinByUserId[u.id] = newPin;
        return;
      }
    }
  }

  /// Après vérification OTP (PIN oublié).
  Future<void> resetPinForIdentifier({
    required String identifier,
    required String newPin,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (newPin.length != kSecretCodeLength) {
      throw Exception('Le PIN doit avoir 4 chiffres.');
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
    _pinByUserId[user.id] = newPin;
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
