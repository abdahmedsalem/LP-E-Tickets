import '../../../domain/models/purchase/payment_method.dart';
import 'payment_method_mapper.dart';
import '../shared_services/acpec_rpc_result_guard.dart';
import '../shared_services/odoo_fueltoken_facade.dart';

class AcpecPaymentMethodsService {
  const AcpecPaymentMethodsService._();

  static Future<List<PaymentMethod>> listActive() async {
    try {
      final raw = await OdooFueltokenFacade().paymentMethods();
      final data = acpecRpcMapOrThrow(
        raw,
        fallbackMessage: 'Moyens de paiement indisponibles.',
      );
      final rawItems = data['items'];
      if (rawItems is! List) return const [];
      final items = <PaymentMethod>[];
      for (final item in rawItems) {
        if (item is! Map) continue;
        try {
          items.add(
            PaymentMethodMapper.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {
          continue;
        }
      }
      return items;
    } catch (_) {
      return const [];
    }
  }
}
