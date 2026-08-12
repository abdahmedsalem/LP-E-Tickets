import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2I pending signup verification resume guard', () {
    test('pending signup store persists only non-secret resume data', () {
      final source = _read('lib/core/auth/pending_signup_store.dart');

      expect(source, contains('ft_pending_signup_phone'));
      expect(source, contains('ft_pending_signup_challenge_id'));
      expect(source, contains('ft_pending_signup_company_id'));
      expect(source, contains('ft_pending_signup_created_at'));
      expect(source, contains('Future<PendingSignup?> loadUsable()'));

      expect(source, isNot(contains('pin')));
      expect(source, isNot(contains('secret_code')));
      expect(source, isNot(contains('code_sms')));
      expect(source, isNot(contains('access_token')));
      expect(source, isNot(contains('refresh_token')));
      expect(source, isNot(contains('device_trust_state')));
    });

    test(
      'register screen saves pending signup before OTP verification route',
      () {
        final source = _read('lib/features/auth/screens/register_screen.dart');
        final storeIndex = source.indexOf('PendingSignupStore.save');
        final routeIndex = source.indexOf("'/register/verify-otp'");

        expect(storeIndex, isNonNegative);
        expect(routeIndex, isNonNegative);
        expect(storeIndex, lessThan(routeIndex));
        expect(source, contains('pin: _pin.text'));
      },
    );

    test('register screen starts fresh instead of resuming old input', () {
      final source = _read('lib/features/auth/screens/register_screen.dart');

      expect(source, contains('int _activeStep = 1;'));
      expect(source, contains('unawaited(PendingSignupStore.clear())'));
      expect(source, isNot(contains('PendingSignupStore.loadUsable()')));
      expect(source, isNot(contains('loadDraftUsable')));
    });

    test('router allows register verify OTP route without extra args', () {
      final source = _read('lib/core/router/app_router.dart');

      expect(source, contains("path: '/register/verify-otp'"));
      expect(source, contains('args: x is RegisterOtpRouteArgs ? x : null'));
      expect(source, isNot(contains('Reprendre depuis l\'inscription.')));
    });

    test(
      'verify screen resumes pending signup and returns to fresh register',
      () {
        final source = _read(
          'lib/features/auth/screens/register_verify_otp_screen.dart',
        );

        expect(source, contains('PendingSignupStore.loadUsable()'));
        expect(source, contains('PendingSignupStore.clear()'));
        expect(source, contains('PendingSignupStore.save('));
        expect(source, contains('final _pin = TextEditingController();'));
        expect(source, contains('bool get _needsPinEntry'));
        expect(source, contains('l10n.authConfirmPin'));
        expect(source, contains('validateFourDigitNumericPassword(pin)'));
        expect(source, contains('pin: pin'));
        expect(source, contains('class _MissingRegisterOtpScreen'));
        expect(source, contains('Future<void> _leaveVerification()'));
        expect(source, contains("context.go('/register')"));
        expect(source, isNot(contains('context.canPop()')));
        expect(source, isNot(contains('context.pop()')));
      },
    );

    test('splash resumes pending signup before onboarding/login fallback', () {
      final source = _read('lib/features/auth/screens/splash_screen.dart');

      final pendingIndex = source.indexOf('PendingSignupStore.loadUsable()');
      final onboardingIndex = source.indexOf(
        'AppPreferences.hasSeenOnboarding()',
      );

      expect(pendingIndex, isNonNegative);
      expect(onboardingIndex, isNonNegative);
      expect(pendingIndex, lessThan(onboardingIndex));
      expect(source, contains("context.go('/register/verify-otp')"));
    });

    test('remote registration does not initialize a local unlock PIN', () {
      final source = _read('lib/features/auth/bloc/auth_bloc.dart');
      final start = source.indexOf(
        'Future<void> _onRemoteRegistrationCompleted(',
      );
      final end = source.indexOf('Future<void> _onSessionEstablished(', start);

      expect(start, isNonNegative);
      expect(end, isNonNegative);

      final method = source.substring(start, end);
      final adoptIndex = method.indexOf('_repo.adoptRemoteUser');
      final emitIndex = method.indexOf('AuthStatus.authenticated');

      expect(adoptIndex, isNonNegative);
      expect(emitIndex, isNonNegative);
      expect(adoptIndex, lessThan(emitIndex));
      expect(method, contains('Ne pas'));
      expect(method, isNot(contains('saveLocalUnlockPinForCurrentUser')));
      expect(method, isNot(contains('AuthStatus.pinSetupRequired')));
    });

    test(
      'compact register header does not render overflowing logo wordmark',
      () {
        final source = _read('lib/features/auth/screens/register_screen.dart');
        final start = source.indexOf('class _RegisterCompactHeader');
        final end = source.indexOf('\nclass _Register', start + 1);

        expect(start, isNonNegative);
        expect(end, isNonNegative);
        expect(source, isNot(contains('class _RegisterWelcomeCopy')));
        expect(source, isNot(contains('class _RegisterSectionTitle')));

        final header = source.substring(start, end);
        expect(header, contains('FuelLogo'));
        expect(header, contains('showOrgWordmark: false'));
        expect(
          header,
          isNot(contains("subtitleFuelToken: 'Tickets Carburant'")),
        );
        expect(header, contains('l10n.authRegisterBrand'));
      },
    );
  });
}
