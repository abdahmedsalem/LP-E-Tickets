import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/sensitive_action_intent.dart';

void main() {
  group('SensitiveActionIntent', () {
    test('keeps one idempotency key for the same user intention', () {
      final intent = SensitiveActionIntent.create('qr issue');

      final first = intent.authParams('1234');
      final retry = intent.authParams('1234');

      expect(first['idempotency_key'], retry['idempotency_key']);
      expect(first['idempotency_key'], intent.idempotencyKey);
      expect(first['idempotency_key'].toString(), startsWith('ft-qr-issue-'));
    });

    test('sends only canonical sensitive auth keys', () {
      final intent = SensitiveActionIntent.create('station/qr/use');
      final params = intent.withAuthParams({
        'public_code': 'SEC-QR-001',
      }, actionCode: ' 1234 ');

      expect(params['public_code'], 'SEC-QR-001');
      expect(params['action_code'], '1234');
      expect(params['idempotency_key'], intent.idempotencyKey);
      expect(params.containsKey('pin'), isFalse);
      expect(params.containsKey('action_pin'), isFalse);
      expect(params.containsKey('secret_code'), isFalse);
    });
  });
}
