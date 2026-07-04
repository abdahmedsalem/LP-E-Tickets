import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch33B server confirm PIN unlock guard', () {
    test('hydrate restores server session into server PIN lock, not home', () {
      final source = _read('lib/features/auth/bloc/auth_bloc.dart');

      expect(source, contains('tryRestoreRemoteSession();'));
      expect(source, contains('AuthStatus.locked'));
      expect(source, contains('confirmation PIN serveur'));
      expect(
        source,
        isNot(contains('final hasLocalPin = await _repo.hasLocalUnlockPin')),
      );
      expect(source, isNot(contains('_localPinResetRequiredMessage')));
      expect(
        source,
        isNot(
          contains(
            'emit(AuthState(status: AuthStatus.authenticated, user: user));\n'
            '    }\n\n'
            '  Future<void> _onActivationRefresh',
          ),
        ),
      );
    });

    test('unlock uses backend confirm-pin, not local PIN comparison', () {
      final bloc = _read('lib/features/auth/bloc/auth_bloc.dart');
      final repo = _read('lib/data/repositories/auth_repository.dart');
      final service = _read('lib/data/services/odoo_auth_service.dart');
      final config = _read('lib/core/config/odoo_auth_rpc_config.dart');

      expect(bloc, contains('_repo.confirmOpenPin(e.pin)'));
      expect(repo, contains('Future<AppUser> confirmOpenPin(String pin)'));
      expect(repo, contains('OdooAuthService.instance.confirmSessionPin'));
      expect(service, contains('Future<void> confirmSessionPin'));
      expect(service, contains("'action_code': code"));
      expect(config, contains("'/api/acpec/mobile_auth/v1/confirm-pin'"));
      expect(config, contains('hasConfirmPin'));
    });

    test('unlock fails closed if server confirm-pin is unavailable', () {
      final repo = _read('lib/data/repositories/auth_repository.dart');

      expect(repo, contains('Vérification PIN serveur indisponible'));
      expect(repo, contains('if (!_usesServerConfirmPin)'));
      expect(repo, isNot(contains('unlockWithLocalPin')));
      expect(repo, isNot(contains('return unlockWithLocalPin(pin);')));
      expect(repo, isNot(contains('AppEnvironment.allowOfflineDemoInRelease')));
      expect(repo, isNot(contains('kReleaseMode')));
    });

    test('frontend no longer keeps any local unlock PIN cache', () {
      final repo = _read('lib/data/repositories/auth_repository.dart');
      final cache = _read('lib/core/auth/login_session_cache.dart');
      final bloc = _read('lib/features/auth/bloc/auth_bloc.dart');
      final forgot = _read(
        'lib/features/auth/screens/forgot_otp_flow_screens.dart',
      );

      for (final source in [repo, cache, bloc, forgot]) {
        expect(source, isNot(contains('unlockWithLocalPin')));
        expect(source, isNot(contains('hasLocalUnlockPin')));
        expect(source, isNot(contains('saveLocalUnlockPinForCurrentUser')));
        expect(source, isNot(contains('syncLocalPinIfExists')));
        expect(source, isNot(contains('_pinByUserId')));
        expect(source, isNot(contains('_useLocalPinCache')));
        expect(source, isNot(contains('_allowLocalPinFallback')));
        expect(source, isNot(contains('AuthLocalPinSetupRequested')));
        expect(source, isNot(contains('pinSetupRequired')));
        expect(source, isNot(contains('ft_last_pin')));
        expect(source, isNot(contains('saveLastPin')));
        expect(source, isNot(contains('lastPin')));
        expect(source, isNot(contains('hasLastPin')));
        expect(source, isNot(contains('verifyLastPin')));
      }
    });

    test('OTP login no longer requires or creates local unlock PIN', () {
      final source = _read('lib/features/auth/bloc/auth_bloc.dart');
      final start = source.indexOf('Future<void> _onLoginOtpVerified(');
      final end = source.indexOf('Future<void> _onRegister(', start);

      expect(start, isNonNegative);
      expect(end, isNonNegative);
      final method = source.substring(start, end);

      expect(method, contains('verifyLoginOtp'));
      expect(method, contains('PIN local n\'est plus requis'));
      expect(method, isNot(contains('hasLocalUnlockPin')));
      expect(method, isNot(contains('saveLocalUnlockPinForCurrentUser')));
      expect(method, isNot(contains('AuthStatus.pinSetupRequired')));
    });

    test('PIN lock screen dispatches only server unlock', () {
      final source = _read(
        'lib/features/auth/screens/session_pin_lock_screen.dart',
      );

      expect(source, contains('AuthUnlockRequested(pin: pin)'));
      expect(source, contains('PIN serveur'));
      expect(source, isNot(contains('AuthLocalPinSetupRequested(pin: pin)')));
      expect(
        source,
        isNot(contains('state.status == AuthStatus.pinSetupRequired')),
      );
      expect(source, isNot(contains('Confirmer le PIN')));
    });

    test('public confirm-pin codes are mapped locally', () {
      final source = _read('lib/data/services/acpec_public_api_error.dart');

      expect(source, contains('INVALID_ACTION_CODE'));
      expect(source, contains('ACTION_CODE_LOCKED'));
      expect(source, contains('PIN_RESET_REQUIRED'));
      expect(source, contains('MISSING_ACTION_CODE'));
      expect(source, contains('INVALID_ACTION_CODE_KEY'));
      expect(source, contains('DEVICE_PENDING_TRUST'));
      expect(source, contains('DEVICE_BLOCKED'));
    });

    test('token and Odoo session stores use secure storage migration', () {
      final pubspec = _read('pubspec.yaml');
      final secureKv = _read('lib/core/auth/secure_kv.dart');
      final tokenStore = _read('lib/core/auth/auth_token_store.dart');
      final sessionStore = _read('lib/core/auth/odoo_session_store.dart');

      expect(pubspec, contains('flutter_secure_storage:'));
      expect(secureKv, contains('FlutterSecureStorage'));
      expect(
        secureKv,
        contains('AndroidOptions(encryptedSharedPreferences: true)'),
      );
      expect(secureKv, contains('readMigratingSharedPreference'));
      expect(secureKv, contains('SharedPreferences.getInstance'));

      expect(tokenStore, contains("import 'secure_kv.dart';"));
      expect(tokenStore, contains('SecureKv.write(_kAccess'));
      expect(tokenStore, contains('SecureKv.readMigratingSharedPreference'));
      expect(tokenStore, contains('SecureKv.delete(_kAccess'));
      expect(tokenStore, isNot(contains('SharedPreferences.getInstance')));
      expect(tokenStore, isNot(contains("package:shared_preferences")));

      expect(sessionStore, contains("import 'secure_kv.dart';"));
      expect(sessionStore, contains('SecureKv.write(_kSessionId'));
      expect(sessionStore, contains('SecureKv.readMigratingSharedPreference'));
      expect(sessionStore, contains('SecureKv.delete(_kSessionId'));
      expect(sessionStore, isNot(contains('SharedPreferences.getInstance')));
      expect(sessionStore, isNot(contains("package:shared_preferences")));
    });

    test(
      'Android backup remains disabled while secrets move to secure storage',
      () {
        final manifest = _read('android/app/src/main/AndroidManifest.xml');

        expect(manifest, contains('android:allowBackup="false"'));
        expect(manifest, contains('android:fullBackupContent="false"'));
      },
    );

    test('foreground idle and app lifecycle request lock, not logout', () {
      final main = _read('lib/main.dart');
      final bloc = _read('lib/features/auth/bloc/auth_bloc.dart');

      expect(main, contains('_idleLockDelay = Duration(minutes: 3)'));
      expect(main, contains('_scheduleIdleLock'));
      expect(main, contains('AuthLockReason.idleTimeout'));
      expect(main, contains('AuthLockReason.appLifecycle'));
      expect(main, contains('AppLifecycleState.paused'));
      expect(main, contains('AppLifecycleState.inactive'));
      expect(main, contains('AppLifecycleState.hidden'));
      expect(main, contains('AppLifecycleState.detached'));
      expect(
        main,
        contains('_authBloc.add(AuthLockRequested(reason: reason))'),
      );
      expect(
        main,
        isNot(contains('_authBloc.add(const AuthLogoutRequested())')),
      );

      expect(bloc, contains('enum AuthLockReason'));
      expect(bloc, contains('class AuthLockRequested extends AuthEvent'));
      expect(bloc, contains('on<AuthLockRequested>(_onLockRequested)'));
      expect(bloc, contains('Future<void> _onLockRequested'));
      expect(bloc, contains('state.status != AuthStatus.authenticated'));
      expect(bloc, contains('status: AuthStatus.locked'));
    });

    test('resume does not refresh sensitive data when a lock is pending', () {
      final main = _read('lib/main.dart').replaceAll('\\r\\n', '\\n');

      expect(main, contains('didChangeAppLifecycleState'));
      expect(main, contains('_sessionLockRequested'));
      expect(main, contains('WalletRefreshBus.instance.bump();'));

      final lifecycle = main.indexOf('didChangeAppLifecycleState');
      final guard = main.indexOf(
        'if (_authBloc.state.status != AuthStatus.authenticated',
        lifecycle,
      );
      final sessionLockGuard = main.indexOf('_sessionLockRequested', guard);
      final wallet = main.indexOf(
        'WalletRefreshBus.instance.bump();',
        lifecycle,
      );

      expect(lifecycle, isNonNegative);
      expect(guard, isNonNegative);
      expect(sessionLockGuard, isNonNegative);
      expect(wallet, isNonNegative);
      expect(guard, lessThan(wallet));
      expect(sessionLockGuard, lessThan(wallet));
    });
  });
}
