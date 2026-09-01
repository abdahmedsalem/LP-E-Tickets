import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payment methods come exclusively from the backend', () {
    final model = File(
      'lib/data/models/payment_method_config.dart',
    ).readAsStringSync();
    final service = File(
      'lib/data/services/acpec_payment_methods_service.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/purchases/screens/submit_purchase_screen.dart',
    ).readAsStringSync();

    expect(model, isNot(contains('fallbackMethods')));
    expect(model, isNot(contains("name: 'Bankily'")));
    expect(model, isNot(contains("name: 'Sedad'")));
    expect(model, isNot(contains("name: 'Masrivi'")));
    expect(service, contains('OdooFueltokenFacade().paymentMethods()'));
    expect(service, isNot(contains('fallbackMethods')));
    expect(screen, contains('List<PaymentMethodConfig> _paymentMethods = []'));
    expect(screen, contains('Aucun moyen de paiement disponible.'));
    expect(screen, contains('_selectedPaymentMethodConfig != null'));
  });
}
