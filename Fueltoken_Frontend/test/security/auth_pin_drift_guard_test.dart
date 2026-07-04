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
      expect(source, isNot(contains('final hasLocalPin = await _repo.hasLocalUnlockPin')));
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
      expect(source, isNot(contains('state.status == AuthStatus.pinSetupRequired')));
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
  });
}
