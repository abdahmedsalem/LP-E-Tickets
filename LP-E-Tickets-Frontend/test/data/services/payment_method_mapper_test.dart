import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/purchase_services/payment_method_mapper.dart';
import 'package:fueltoken_app/domain/models/purchase/payment_method.dart';

void main() {
  test('maps a backend payment method into the domain model', () {
    final method = PaymentMethodMapper.fromJson({
      'id': '12',
      'code': 'BANKILY',
      'display_name': 'Bankily',
      'merchant_code': '27919822',
      'instructions': 'Pay this number',
      'color_hex': '#123456',
      'image_128': 'aGVsbG8=',
    });

    expect(method, isA<PaymentMethod>());
    expect(method.id, 12);
    expect(method.code, 'bankily');
    expect(method.name, 'Bankily');
    expect(method.merchantCode, '27919822');
    expect(method.instructions, 'Pay this number');
    expect(method.colorHex, '#123456');
    expect(method.logoData, 'aGVsbG8=');
  });

  test('rejects incomplete payment method records', () {
    expect(
      () => PaymentMethodMapper.fromJson({'code': 'bankily'}),
      throwsFormatException,
    );
  });
}
