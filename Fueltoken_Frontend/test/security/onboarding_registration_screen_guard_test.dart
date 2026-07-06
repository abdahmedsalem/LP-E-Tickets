import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2H onboarding registration screen guard', () {
    test('splash routes first unauthenticated opening to onboarding', () {
      final splash = _read('lib/features/auth/screens/splash_screen.dart');
      final prefs = _read('lib/core/settings/app_preferences.dart');
      final router = _read('lib/core/router/app_router.dart');

      expect(prefs, contains('_kHasSeenOnboarding'));
      expect(prefs, contains('Future<bool> hasSeenOnboarding()'));
      expect(prefs, contains('Future<void> setHasSeenOnboarding(bool value)'));
      expect(splash, contains('PendingSignupStore.loadUsable()'));
      expect(splash, contains("context.go('/register/verify-otp')"));
      expect(splash, contains('AppPreferences.hasSeenOnboarding()'));
      expect(splash, contains("seenOnboarding ? '/login' : '/onboarding'"));
      expect(router, contains("path: '/onboarding'"));
      expect(router, contains('const OnboardingScreen()'));
    });

    test(
      'onboarding has logo, signup CTA and login link but no language switch',
      () {
        final source = _read(
          'lib/features/auth/screens/onboarding_screen.dart',
        );

        expect(source, contains('Tickets Carburant'));
        expect(source, contains('Créer mon compte'));
        expect(source, contains('Vous avez déjà un compte ?'));
        expect(source, contains('Se connecter'));
        expect(source, contains('setHasSeenOnboarding(true)'));
        expect(source, contains('context.go(route)'));
        expect(source, isNot(contains('LanguageSwitch')));
        expect(source, isNot(contains("'FR'")));
        expect(source, isNot(contains("'AR'")));
      },
    );

    test(
      'registration requires MR phone, PIN and PIN confirmation before submit',
      () {
        final source = _read('lib/features/auth/screens/register_screen.dart');

        expect(
          source,
          contains('final _phoneLocal = TextEditingController();'),
        );
        expect(source, contains('final _pin = TextEditingController();'));
        expect(
          source,
          contains('final _pinConfirm = TextEditingController();'),
        );
        expect(source, contains('String get _phoneLocalDigits'));
        expect(
          source,
          contains('validateMrLocalPhone(_phoneLocal.text) == null'),
        );
        expect(source, contains('maxLength: 8'));
        expect(source, isNot(contains("'+222'")));
        expect(source, isNot(contains('prefix:')));
        expect(
          source,
          contains('validateFourDigitNumericPassword(pin) == null'),
        );
        expect(source, contains('_pinConfirm.text.trim() == pin'));
        expect(source, contains("hint: 'Confirmer le PIN'"));
        expect(
          source,
          contains('onPressed: canSubmit ? _onCreateAccount : null'),
        );
        expect(source, contains('const _RegisterCompactHeader()'));
        expect(source, contains('Leader Petroleum — Tickets Carburant'));
        expect(
          source,
          contains('Recevez un code SMS pour vérifier votre compte.'),
        );
        expect(source, isNot(contains('const _RegisterWelcomeCopy(),')));
        expect(
          source,
          contains('if (_sendingOtp || !_formLooksValid) return;'),
        );
      },
    );

    test(
      'registration keeps backend OTP contract technical names unchanged',
      () {
        final source = _read('lib/features/auth/screens/register_screen.dart');

        expect(source, contains('OdooAuthService.instance.requestSignupOtp'));
        expect(source, contains('PendingSignupStore.save'));
        expect(source, contains('RegisterOtpRouteArgs('));
        expect(source, contains('challengeId: challengeId'));
        expect(source, contains('pin: _pin.text'));
        expect(source, contains('name: _name.text.trim()'));
        expect(source, contains('phoneFull: _phoneLocalDigits'));
        expect(source, isNot(contains('signup_identifier')));
        expect(source, isNot(contains('secret_code')));
      },
    );

    test('auth user-facing copy says SMS instead of OTP', () {
      final register = _read('lib/features/auth/screens/register_screen.dart');
      final registerVerify = _read(
        'lib/features/auth/screens/register_verify_otp_screen.dart',
      );
      final forgot = _read(
        'lib/features/auth/screens/forgot_otp_flow_screens.dart',
      );
      final repo = _read('lib/data/repositories/auth_repository.dart');

      expect(register, contains('Code SMS envoyé.'));
      expect(
        register,
        isNot(
          contains(
            'Code '
            'OTP envoyé',
          ),
        ),
      );

      expect(registerVerify, contains('Code SMS introuvable'));
      expect(
        registerVerify,
        isNot(
          contains(
            'Code '
            'OTP introuvable',
          ),
        ),
      );

      expect(forgot, contains('Saisissez le code SMS'));
      expect(forgot, contains("labelText: 'Code SMS'"));
      expect(
        forgot,
        isNot(
          contains(
            "labelText: 'Code ' "
            "'OTP'",
          ),
        ),
      );

      expect(repo, contains('Connexion par SMS indisponible.'));
      expect(repo, contains('Vérification par SMS indisponible.'));
      expect(
        repo,
        isNot(
          contains(
            'Connexion '
            'OTP ACPEC indisponible.',
          ),
        ),
      );
      expect(
        repo,
        isNot(
          contains(
            'Vérification '
            'OTP ACPEC indisponible.',
          ),
        ),
      );
    });
  });
}
