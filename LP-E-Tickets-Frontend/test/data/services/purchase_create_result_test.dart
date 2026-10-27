import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/purchase_services/acpec_purchases_mapper.dart';

void main() {
  test('creation accepts supported envelopes and identifier aliases', () {
    for (final identifierKey in ['purchase_id', 'id', 'order_id']) {
      final data = {
        identifierKey: 12,
        'public_code': 'PUB12',
        'operation_reference': 'TX-20261026-134604-0001',
        'payment_reference': 'REF12',
        'payment_method_name': 'Bankily',
        'payment_merchant_code': '12345',
      };
      for (final response in [
        data,
        {'ok': true, 'data': data},
      ]) {
        final receipt = AcpecPurchasesMapper.parseCreateResult(response);
        expect(receipt.purchaseId, '12');
        expect(receipt.publicCode, 'PUB12');
        expect(receipt.operationReference, 'TX-20261026-134604-0001');
        expect(receipt.state, 'submitted');
        expect(receipt.paymentReference, 'REF12');
        expect(receipt.paymentMethodName, 'Bankily');
        expect(receipt.paymentMerchantCode, '12345');
      }
    }
  });

  test('payment snapshot fields remain optional for older API responses', () {
    final receipt = AcpecPurchasesMapper.parseCreateResult({
      'purchase_id': 12,
      'public_code': 'PUB12',
      'payment_method_name': false,
      'payment_merchant_code': false,
    });

    expect(receipt.paymentMethodName, isNull);
    expect(receipt.paymentMerchantCode, isNull);
  });

  test('invalid identifiers cannot produce a successful purchase receipt', () {
    for (final id in [null, '', 0, -1, false, 'invalid']) {
      expect(
        () => AcpecPurchasesMapper.parseCreateResult({
          'purchase_id': id,
          'public_code': 'PUB12',
        }),
        throwsException,
      );
    }
  });

  test('missing public code and refused creation never produce a receipt', () {
    for (final response in [
      null,
      {'purchase_id': 12},
      {'ok': false, 'message': 'Refus'},
      {
        'data': {'ok': false, 'message': 'Refus'},
      },
    ]) {
      expect(
        () => AcpecPurchasesMapper.parseCreateResult(response),
        throwsException,
      );
    }
  });
}
