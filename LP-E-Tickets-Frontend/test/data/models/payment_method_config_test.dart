import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/domain/models/purchase/payment_method.dart';

PaymentMethod _method(String destination) =>
    PaymentMethod(code: 'test', name: 'Test', merchantCode: destination);

void main() {
  test('destinations are always displayed as merchant codes', () {
    for (final value in ['12345', '123456', 'SEDAD-42']) {
      final method = _method(value);

      expect(method.destinationLabel, 'Code commerçant');
      expect(method.destinationCopiedLabel, 'Code commerçant');
    }
  });
}
