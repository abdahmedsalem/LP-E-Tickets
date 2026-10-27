import '../../../domain/models/purchase/payment_method.dart';
import '../shared_services/acpec_rpc_result_guard.dart';
import '../shared_services/odoo_fueltoken_facade.dart';
import 'payment_method_mapper.dart';

class AcpecPaymentMethodsService {
  const AcpecPaymentMethodsService._();

  static Future<List<PaymentMethod>> listActive({
    OdooFueltokenFacade? api,
  }) async {
    final response = await (api ?? OdooFueltokenFacade()).paymentMethods();
    final responseData = acpecRpcMapOrThrow(
      response,
      fallbackMessage: 'Moyens de paiement indisponibles.',
    );
    final responseItems = responseData['items'];
    if (responseItems is! List) {
      throw const FormatException('Liste des moyens de paiement invalide.');
    }

    final paymentMethods = <PaymentMethod>[];
    for (final paymentMethodData in responseItems) {
      if (paymentMethodData is! Map) {
        throw const FormatException('Moyen de paiement invalide.');
      }
      paymentMethods.add(
        PaymentMethodMapper.fromJson(
          Map<String, dynamic>.from(paymentMethodData),
        ),
      );
    }
    return paymentMethods;
  }
}
