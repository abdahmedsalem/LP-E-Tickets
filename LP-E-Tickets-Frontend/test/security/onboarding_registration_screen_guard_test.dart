import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2H onboarding registration screen guard', () {
    test('splash requests language before first onboarding', () {
      final splash = _read('lib/features/auth/screens/splash_screen.dart');
      final prefs = _read('lib/core/settings/app_preferences.dart');
      final router = _read('lib/core/router/app_router.dart');

      expect(prefs, contains('_kHasSeenOnboarding'));
      expect(prefs, contains('_kHasSelectedLanguage'));
      expect(prefs, contains('Future<bool> hasSelectedLanguage()'));
      expect(prefs, contains('Future<bool> hasSeenOnboarding()'));
      expect(prefs, contains('Future<void> setHasSeenOnboarding(bool value)'));
      expect(splash, contains('PendingSignupStore.loadUsable()'));
      expect(splash, contains('AppPreferences.hasSelectedLanguage()'));
      expect(splash, contains("context.go('/language-selection')"));
      expect(splash, contains("context.go('/register/verify-otp')"));
      expect(splash, contains('AppPreferences.hasSeenOnboarding()'));
      expect(splash, contains("seenOnboarding ? '/login' : '/onboarding'"));
      expect(router, contains("path: '/onboarding'"));
      expect(router, contains("path: '/language-selection'"));
      expect(router, contains('const OnboardingScreen()'));
    });

    test(
      'onboarding has logo, signup CTA and login link but no language switch',
      () {
        final source = _read(
          'lib/features/auth/screens/onboarding_screen.dart',
        );

        expect(source, contains('l10n.authWelcomeTitle'));
        expect(source, contains('l10n.authCreateAccount'));
        expect(source, contains('l10n.authAlreadyAccount'));
        expect(source, contains('l10n.authSignIn'));
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
        expect(source, contains('hint: l10n.authConfirmPin'));
        expect(source, contains('onPressed: canSubmit'));
        expect(source, contains('_onCreateAccount'));
        expect(source, contains('const _RegisterCompactHeader()'));
        expect(source, contains('l10n.authRegisterBrand'));
        expect(
          source,
          contains('l10n.authRegisterInstruction'),
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
        final authService = _read('lib/data/services/odoo_auth_service.dart');
        final register = _read('lib/features/auth/screens/register_screen.dart');

        expect(authService, contains("'purpose': 'register'"));
        expect(authService, contains('requestSignupOtp'));
        expect(register, contains('_challengeId'));
        expect(register, contains("'/register/verify-otp'"));
      },
    );

    test('auth user-facing copy in arb catalogs does not contain OTP', () {
      final l10nFr = _read('lib/l10n/app_fr.arb');
      final l10nAr = _read('lib/l10n/app_ar.arb');

      expect(l10nFr, isNot(contains('OTP')));
      expect(l10nAr, isNot(contains('OTP')));
    });
  });
}
