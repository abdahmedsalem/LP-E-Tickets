import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/models/payment_method_config.dart';

PaymentMethodConfig _method(String destination) =>
    PaymentMethodConfig(code: 'test', name: 'Test', merchantCode: destination);

void main() {
  test('8 digits are displayed as a phone number', () {
    final method = _method('27 91-98 22');

    expect(method.destinationIsPhoneNumber, isTrue);
    expect(method.destinationIsMerchantCode, isFalse);
    expect(method.destinationLabel, 'Numéro de téléphone');
    expect(method.destinationCopiedLabel, 'Numéro');
  });

  test('4 or 6 digits are displayed as a merchant code', () {
    for (final value in ['1234', '123456']) {
      final method = _method(value);

      expect(method.destinationIsMerchantCode, isTrue);
      expect(method.destinationIsPhoneNumber, isFalse);
      expect(method.destinationLabel, 'Code commerçant');
      expect(method.destinationCopiedLabel, 'Code commerçant');
    }
  });

  test('other formats keep the generic compatible label', () {
    final method = _method('ABC-123');

    expect(method.destinationIsPhoneNumber, isFalse);
    expect(method.destinationIsMerchantCode, isFalse);
    expect(method.destinationLabel, 'Code commerçant / Numéro de téléphone');
    expect(method.destinationCopiedLabel, 'Identifiant de paiement');
  });
}
