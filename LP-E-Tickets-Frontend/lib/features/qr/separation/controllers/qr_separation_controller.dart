import '../../shared/controllers/qr_flow_controller.dart';

/// QR separation flow: load the source QR, validate the split, refresh data.
class QrSeparationController extends QrFlowController {
  QrSeparationController({required super.repository});

  Future<Map<String, dynamic>> separate(
    Map<String, dynamic> params, {
    required String fallbackMessage,
    required String publicErrorMessage,
  }) => execute(
    'separate',
    () => repository.qrSeparer(
      params,
      fallbackMessage: fallbackMessage,
      publicErrorMessage: publicErrorMessage,
    ),
  );
}
