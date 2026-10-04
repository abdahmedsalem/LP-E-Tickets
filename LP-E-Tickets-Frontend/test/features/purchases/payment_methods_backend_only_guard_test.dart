import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payment methods come exclusively from the backend', () {
    final model = File(
      'lib/domain/models/purchase/payment_method.dart',
    ).readAsStringSync();
    final mapper = File(
      'lib/data/services/purchase_services/payment_method_mapper.dart',
    ).readAsStringSync();
    final service = File(
      'lib/data/services/purchase_services/acpec_payment_methods_service.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/purchases/screens/submit_purchase_screen.dart',
    ).readAsStringSync();

    expect(model, isNot(contains('fallbackMethods')));
    expect(model, isNot(contains("name: 'Bankily'")));
    expect(model, isNot(contains("name: 'Sedad'")));
    expect(model, isNot(contains("name: 'Masrivi'")));
    expect(mapper, contains("json['merchant_code']"));
    expect(service, contains('OdooFueltokenFacade().paymentMethods()'));
    expect(service, isNot(contains('fallbackMethods')));
    expect(screen, contains('List<PaymentMethod> _paymentMethods = []'));
    expect(
      screen,
      contains('AppLocalizations.of(context).purchaseNoPaymentMethods'),
    );
    expect(screen, contains('_selectedPaymentMethodConfig != null'));
  });
}
