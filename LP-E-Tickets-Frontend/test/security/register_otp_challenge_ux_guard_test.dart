import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, isNonNegative, reason: 'Missing start marker: $start');
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, isNonNegative, reason: 'Missing end marker: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  group('Register SMS challenge UX guard', () {
    test('signup OTP request uses the public identifier contract', () {
      final source = _read(
        'lib/data/services/auth_services/odoo_auth_service.dart',
      );
      final method = _between(
        source,
        'Future<Map<String, dynamic>> requestSignupOtp({',
        'Future<Map<String, dynamic>> verifySignupOtp({',
      );

      expect(method, contains("'identifier': local"));
      expect(method, contains("'purpose': 'register'"));
      expect(method, isNot(contains("'signup_identifier'")));
    });

    test(
      'registration screen consumes a typed challenge before navigation',
      () {
        final source = _read('lib/features/auth/screens/register_screen.dart');
        final mapper = _read(
          'lib/data/services/auth_services/signup_response_mapper.dart',
        );

        expect(source, contains('challenge.challengeId'));
        expect(source, contains('challengeId == null || challengeId <= 0'));
        expect(source, contains('challenge.expiresInSeconds'));
        expect(source, contains('authSmsNotConfirmed'));
        expect(source, isNot(contains('_extractChallengeId')));
        expect(mapper, contains("data['otp_challenge_id']"));
        expect(mapper, contains("data['challenge_id']"));
        expect(mapper, isNot(contains('otp_challenge_ref')));
        expect(mapper, isNot(contains('challenge_ref')));
      },
    );

    test(
      'verify OTP keeps support reference but gives a contextual SMS UX',
      () {
        final source = _read(
          'lib/features/auth/screens/register_verify_otp_screen.dart',
        );

        expect(source, contains('ErrorPresenter.isRpcError(error)'));
        expect(source, contains('ErrorPresenter.publicErrorCode('));
        expect(source, contains('authOtpMissingExpired'));
        expect(source, contains('supportReference(ref)'));
        expect(source, contains('result.hasSessionTokens'));
        expect(source, isNot(contains('_extractTokens')));
        expect(source, isNot(contains('debug_reason')));
      },
    );

    test('signup OTP verification sends challenge id when available', () {
      final source = _read(
        'lib/data/services/auth_services/odoo_auth_service.dart',
      );
      final method = _between(
        source,
        'Future<Map<String, dynamic>> verifySignupOtp({',
        'Future<Map<String, dynamic>> requestSignupOtpResend({',
      );

      expect(
        method,
        contains(
          "if (challengeId != null && challengeId > 0) 'challenge_id': challengeId",
        ),
      );
      expect(method, contains("'identifier': idForRpc"));
      expect(method, contains("'purpose': 'register'"));
      expect(method, contains("'device_uid': deviceUid"));
    });
  });
}
