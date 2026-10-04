import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'QR confirmation locks before navigation and checks widget lifetime',
    () {
      final source = File(
        'lib/features/qr/generation/screens/emit_qr_screen.dart',
      ).readAsStringSync();
      expect(source, contains('if (_confirmingEmit || _emitting) return;'));
      expect(
        source.indexOf('_confirmingEmit = true;'),
        lessThan(source.indexOf('await _openEmitConfirmation(context)')),
      );
      expect(
        source,
        contains('if (!mounted) return;\n    if (actionCode != null'),
      );
    },
  );
  group('QR issue refresh cache guard', () {
    test(
      'QR issue invalidates every paginated QR cache entry before refresh bus',
      () {
        final source = File(
          'lib/features/qr/generation/screens/emit_qr_screen.dart',
        ).readAsStringSync();

        final repository = File(
          'lib/data/repositories/qr_generation_repository.dart',
        ).readAsStringSync();
        expect(source, contains('_refreshClientReadModelsAfterQrIssue'));
        expect(repository, contains('invalidateRoute('));
        expect(repository, contains('OdooFueltokenRpcConfig.qrList'));

        final controller = File(
          'lib/features/qr/generation/controllers/qr_generation_controller.dart',
        ).readAsStringSync();
        expect(
          controller.indexOf('_repository.invalidateAfterIssue();'),
          lessThan(controller.indexOf('return result;')),
        );
        expect(source, contains('await _controller.qrIssue('));
        expect(source, contains('QrRefreshBus.instance.bump();'));
      },
    );

    test('QR issue still refreshes wallet, faces and client history', () {
      final source = File(
        'lib/features/qr/generation/screens/emit_qr_screen.dart',
      ).readAsStringSync();

      expect(source, contains('FacesRefreshBus.instance.bump();'));
      expect(source, contains('WalletRefreshBus.instance.bump();'));
      expect(source, contains('ClientHistoryRefreshBus.instance.bump();'));
      final repository = File(
        'lib/data/repositories/qr_generation_repository.dart',
      ).readAsStringSync();
      expect(repository, contains('OdooFueltokenRpcConfig.faces'));
      expect(repository, contains('OdooFueltokenRpcConfig.transactions'));
    });
  });
}
