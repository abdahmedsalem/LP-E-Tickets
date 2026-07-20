import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2J initial auth screens branding guard', () {
    test('splash uses Tickets Carburant branding and larger logo', () {
      final source = _read('lib/features/auth/screens/splash_screen.dart');

      expect(source, contains('.authBrandName'));
      expect(source, contains('.authSplashTagline'));

      expect(source, contains('width: 104,'));
      expect(source, contains('height: 104,'));
      expect(source, contains('FuelMark(size: 62)'));
      expect(source, contains('backgroundColor: AppColors.background'));
      expect(source, contains('gradient: AppColors.loginHeroGradient'));
      expect(source, contains('BoxConstraints(maxWidth: 380)'));
      expect(source, contains('TextAlign.center'));

      expect(source, isNot(contains("'FuelToken'")));
    });

    test(
      'signup refused errors are public and do not expose RPC exception type',
      () {
        final register = _read(
          'lib/features/auth/screens/register_screen.dart',
        );
        final publicErrors = _read(
          'lib/data/services/acpec_public_api_error.dart',
        );

        expect(publicErrors, contains("'SIGNUP_NOT_ALLOWED'"));
        expect(
          publicErrors,
          contains('Inscription impossible avec ce numéro.'),
        );
        expect(
          publicErrors,
          contains('Si vous avez déjà un compte, connectez-vous.'),
        );

        expect(register, contains('_registrationErrorMessage(e)'));
        expect(register, contains("error is OdooJsonRpcException"));
        expect(
          register,
          isNot(contains('AppMessage.error(context, e.toString())')),
        );

        expect(register, isNot(contains('Compte existe déjà')));
        expect(register, isNot(contains('Ce compte existe déjà')));
      },
    );

    test(
      'session PIN lock exposes forgotten PIN recovery without dead-end',
      () {
        final source = _read(
          'lib/features/auth/screens/session_pin_lock_screen.dart',
        );

        expect(source, contains('l10n.authForgotPin'));
        expect(source, contains('_openForgotPasswordAfterLogout'));
        expect(source, contains("ctx.go('/forgot-password')"));
        expect(source, contains('AuthLogoutRequested'));

        expect(source, isNot(contains('Se reconnecter par OTP')));
        expect(source, isNot(contains('Créer le PIN de déverrouillage')));
      },
    );
  });
}
