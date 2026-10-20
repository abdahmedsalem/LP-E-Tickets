import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/login_otp_challenge.dart';
import 'package:fueltoken_app/data/services/odoo_jsonrpc_client.dart';

void main() {
  test('unknown account accepted response cannot open SMS verification', () {
    expect(
      () => LoginOtpChallenge.fromResponse({
        'ok': true,
        'data': {'message': 'Si les informations sont valides…'},
      }),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains(LoginOtpChallenge.accountUnavailableMessage),
        ),
      ),
    );
  });

  test('existing accounts accept both server challenge ID keys', () {
    for (final key in ['challenge_id', 'otp_challenge_id']) {
      expect(
        LoginOtpChallenge.fromResponse({
          'ok': true,
          'data': {key: 42},
        }).id,
        42,
      );
    }
  });

  test('invalid responses never produce a challenge or claim no account', () {
    for (final data in [
      null,
      {},
      {'challenge_id': 0},
      {'challenge_id': -1},
      {'challenge_id': 'invalid'},
    ]) {
      expect(
        () => LoginOtpChallenge.fromResponse({'ok': true, 'data': data}),
        throwsFormatException,
      );
    }
  });

  test('business errors remain errors even when a challenge is present', () {
    for (final nested in [false, true]) {
      final refusal = {
        'ok': false,
        'error': {'code': 'RATE_LIMITED'},
        'challenge_id': 42,
      };
      expect(
        () => LoginOtpChallenge.fromResponse(
          nested ? {'ok': true, 'data': refusal} : refusal,
        ),
        throwsA(isA<OdooJsonRpcException>()),
      );
    }
  });
}
