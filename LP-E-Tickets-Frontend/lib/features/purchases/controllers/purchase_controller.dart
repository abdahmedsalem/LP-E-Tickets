import '../../../core/controllers/flow_controller.dart';
import '../../../domain/repositories/purchase_repository.dart';
import '../../../domain/models/purchase/carnet_type.dart';
import '../../../domain/models/purchase/payment_method.dart';
import '../../../domain/models/purchase/purchase_receipt.dart';

class PurchaseController extends FlowController {
  PurchaseController({required PurchaseRepositoryContract repository})
    : _repository = repository;
  final PurchaseRepositoryContract _repository;
  Future<List<CarnetType>> listPurchaseOfferTypes({
    required String companyId,
  }) => execute(
    'offers',
    () => _repository.listPurchaseOfferTypes(companyId: companyId),
  );
  Future<List<PaymentMethod>> listPaymentMethods() =>
      execute('paymentMethods', _repository.listPaymentMethods);
  Future<AcpecPurchaseCreateResult> purchasesCreate(
    Map<String, dynamic> params,
  ) => execute('submit', () => _repository.purchasesCreate(params));
}
