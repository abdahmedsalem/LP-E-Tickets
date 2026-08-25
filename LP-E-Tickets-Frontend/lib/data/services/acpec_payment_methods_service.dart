import '../models/payment_method_config.dart';
import 'acpec_rpc_result_guard.dart';
import 'odoo_fueltoken_facade.dart';

class AcpecPaymentMethodsService {
  const AcpecPaymentMethodsService._();

  static Future<List<PaymentMethodConfig>> listActive() async {
    try {
      final raw = await OdooFueltokenFacade().paymentMethods();
      final data = acpecRpcMapOrThrow(
        raw,
        fallbackMessage: 'Moyens de paiement indisponibles.',
      );
      final rawItems = data['items'];
      if (rawItems is! List) return PaymentMethodConfig.fallbackMethods;
      final items = <PaymentMethodConfig>[];
      for (final item in rawItems) {
        if (item is! Map) continue;
        try {
          items.add(
            PaymentMethodConfig.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {
          continue;
        }
      }
      return items.isEmpty ? PaymentMethodConfig.fallbackMethods : items;
    } catch (_) {
      return PaymentMethodConfig.fallbackMethods;
    }
  }
}
