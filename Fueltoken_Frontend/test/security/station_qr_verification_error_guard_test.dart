import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Station QR verification error guard', () {
    test(
      'scan verification technical error does not become QR non consommable',
      () {
        final source = _read('lib/features/station/screens/scan_screen.dart');

        expect(source, contains('ErrorPresenter.isBackendUnavailable(e)'));
        expect(source, contains('Vérification impossible'));
        expect(source, contains('Retour au scan'));
        expect(source, contains('_restartScannerAfterModal();'));
        expect(source, isNot(contains('on OdooJsonRpcException catch')));
      },
    );

    test('manual verification technical error stays on manual entry', () {
      final source = _read(
        'lib/features/station/screens/station_manual_qr_screen.dart',
      );

      expect(source, contains('ErrorPresenter.isBackendUnavailable(e)'));
      expect(source, contains('Vérification impossible'));
      expect(source, contains('Retour à la saisie'));
      expect(source, contains("if (mounted && !technical)"));
      expect(source, contains("context.go('/station/home')"));
    });

    test(
      'expired scan user goes through auth bloc, not direct login route',
      () {
        final source = _read('lib/features/station/screens/scan_screen.dart');

        expect(source, contains('AuthSessionExpiredRequested'));
        expect(source, isNot(contains("context.go('/login')")));
        expect(source, isNot(contains('state.user!')));
      },
    );
  });
}
