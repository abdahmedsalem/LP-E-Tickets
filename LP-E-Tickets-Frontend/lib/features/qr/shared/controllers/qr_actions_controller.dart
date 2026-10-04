import 'qr_flow_controller.dart';

/// Business operations shared by QR detail, separation and withdrawal screens.
class QrActionsController extends QrFlowController {
  QrActionsController({required super.repository});

  Future<Map<String, dynamic>> qrRetirer(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  }) => execute(
    'mutation',
    () => repository.qrRetirer(
      params,
      fallbackMessage: fallbackMessage,
      publicErrorMessage: publicErrorMessage,
    ),
  );
  Future<Map<String, dynamic>> qrRevealCode(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  }) => execute(
    'mutation',
    () => repository.qrRevealCode(
      params,
      fallbackMessage: fallbackMessage,
      publicErrorMessage: publicErrorMessage,
    ),
  );
}
