import '../models/purchase/carnet_type.dart';
import '../models/purchase/payment_method.dart';
import '../models/purchase/purchase_receipt.dart';

abstract interface class PurchaseRepositoryContract {
  Future<List<CarnetType>> listPurchaseOfferTypes({required String companyId});

  Future<List<PaymentMethod>> listPaymentMethods();

  Future<AcpecPurchaseCreateResult> purchasesCreate(
    Map<String, dynamic> params,
  );
}
