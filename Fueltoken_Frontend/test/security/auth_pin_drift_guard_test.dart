import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2O local PIN drift guard', () {
    test('hydrate never creates local PIN setup after restored server session', () {
      final source = _read('lib/features/auth/bloc/auth_bloc.dart');

      expect(source, contains('tryRestoreRemoteSession();'));
      expect(source, contains('_localPinResetRequiredMessage'));
      expect(
        source,
        contains('créer un nouveau PIN local ici pourrait le désaligner'),
      );
      expect(
        source,
        isNot(
          contains(
            'On garde la session mobile et on force seulement la création du PIN local.',
          ),
        ),
      );
      expect(
        source,
        isNot(
          contains(
            'emit(AuthState(status: AuthStatus.pinSetupRequired, user: user));',
          ),
        ),
      );
    });

    test('OTP login without existing local PIN forces explicit reset flow', () {
      final source = _read('lib/features/auth/bloc/auth_bloc.dart');

      expect(
        source,
        contains('final hasLocalPin = await _repo.hasLocalUnlockPin'),
      );
      expect(source, contains('if (!hasLocalPin) {'));
      expect(source, contains('ne synchronise pas un nouveau PIN'));
      expect(source, contains('await _repo.logout();'));
      expect(
        source,
        isNot(
          contains(
            'status: hasLocalPin\n'
            '              ? AuthStatus.authenticated\n'
            '              : AuthStatus.pinSetupRequired',
          ),
        ),
      );
    });

    test('local PIN setup event is guarded by explicit setup state', () {
      final source = _read('lib/features/auth/bloc/auth_bloc.dart');

      expect(
        source,
        contains(
          'state.status != AuthStatus.pinSetupRequired || state.user == null',
        ),
      );
      expect(source, contains('AuthLocalPinSetupRequested'));
      expect(source, contains('_localPinResetRequiredMessage'));
    });

    test(
      'PIN lock screen only dispatches setup when state is pinSetupRequired',
      () {
        final source = _read(
          'lib/features/auth/screens/session_pin_lock_screen.dart',
        );

        expect(
          source,
          contains('if (state.status == AuthStatus.pinSetupRequired)'),
        );
        expect(source, contains('AuthLocalPinSetupRequested(pin: pin)'));
        expect(source, contains('AuthUnlockRequested(pin: pin)'));
      },
    );
    test('login screen renders local PIN reset information message', () {
      final source = _read('lib/features/auth/screens/login_screen.dart');

      expect(source, contains('state.loginInfoMessage != null'));
      expect(source, contains('message: state.loginInfoMessage!'));
    });
  });
}
