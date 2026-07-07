import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2R station scan doctrine guard', () {
    test('scanner reads QR codes only and ignores non QR detections', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      expect(source, contains('DetectionSpeed.normal'));
      expect(source, contains('autoStart: false'));
      expect(
        source,
        contains('Barcode? _firstQrBarcode(BarcodeCapture capture)'),
      );
      expect(source, contains('barcode.format == BarcodeFormat.qrCode'));
      expect(source, contains('if (barcode == null) return;'));
      expect(
        source,
        contains(
          'if (_leavingAfterSuccess || _processing || _consuming) return;',
        ),
      );
    });

    test('camera has explicit start stop restart and recovery overlay', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      expect(source, contains('bool _startingScanner = false;'));
      expect(source, contains('Future<void> _startScanner()'));
      expect(source, contains('Future<void> _stopScannerForModal()'));
      expect(source, contains('Future<void> _restartScannerAfterModal()'));
      expect(source, contains('_cameraError'));
      expect(source, contains('Réactiver la caméra'));
    });

    test(
      'scan route restarts camera when visible again after shell navigation',
      () {
        final source = _read('lib/features/station/screens/scan_screen.dart');

        expect(source, contains('void _scheduleScannerStartWhenVisible()'));
        expect(source, contains('GoRouterState.of(context).uri.path'));
        expect(source, contains("path == '/station/scan'"));
        expect(source, contains('unawaited(_startScanner());'));
        expect(source, contains('_scheduleScannerStartWhenVisible();'));
      },
    );

    test(
      'station home navigation uses explicit route and resets scan flags',
      () {
        final source = _read('lib/features/station/screens/scan_screen.dart');

        expect(source, contains('void _goStationHome()'));
        expect(source, contains("context.go('/station/home');"));
        expect(source, contains('_processing = false;'));
        expect(source, contains('_consuming = false;'));
        expect(source, contains('_leavingAfterSuccess = false;'));
        expect(source, isNot(contains('context.pop();')));
      },
    );

    test('QR check sheet uses cancel and continue for consumable QR', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      expect(source, contains('Vérification QR'));
      expect(source, contains('Annuler'));
      expect(source, contains('Continuer'));
      expect(source, isNot(contains("'Envoyer'")));
      expect(source, contains('consumeRequested = true;'));
    });

    test(
      'non consumable QR uses only blocking dialog and never check sheet',
      () {
        final source = _read('lib/features/station/screens/scan_screen.dart');

        expect(source, contains("title: 'QR non consommable'"));
        expect(source, contains("actionLabel: 'Retour à l’accueil'"));
        expect(source, contains('result.reason ??'));
        expect(source, contains('_goStationHome();'));

        final resultIndex = source.indexOf(
          'final result = StationQrCheckResult.fromRpc(raw);',
        );
        expect(resultIndex, greaterThanOrEqualTo(0));

        final nonConsumableIndex = source.indexOf(
          'if (!result.canConsume)',
          resultIndex,
        );
        expect(nonConsumableIndex, greaterThan(resultIndex));

        final dialogIndex = source.indexOf(
          '_showFailureDialog(',
          nonConsumableIndex,
        );
        expect(dialogIndex, greaterThan(nonConsumableIndex));

        final sheetIndex = source.indexOf(
          'showModalBottomSheet<void>',
          resultIndex,
        );
        expect(sheetIndex, greaterThan(dialogIndex));

        expect(source, isNot(contains('Consommation bloquée')));
        expect(
          source,
          contains('Le serveur indique que ce QR n’est pas consommable.'),
        );
      },
    );

    test('scan QR check sheet is consumable only', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      expect(source, contains('required this.onConfirmConsume'));
      expect(source, contains('state: QrState.active'));
      expect(source, isNot(contains('widget.onConfirmConsume == null')));
      expect(source, isNot(contains('QrState.blocked')));
      expect(source, isNot(contains('Consommation bloquée')));
    });

    test('PIN cancellation returns to scanner without failure popup', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      final cancelIndex = source.indexOf(
        'if (actionCode == null || actionCode.isEmpty)',
      );
      expect(cancelIndex, greaterThanOrEqualTo(0));

      final restartIndex = source.indexOf(
        'await _restartScannerAfterModal();',
        cancelIndex,
      );
      final returnIndex = source.indexOf('return;', restartIndex);

      expect(restartIndex, greaterThan(cancelIndex));
      expect(returnIndex, greaterThan(restartIndex));
    });

    test('scan consume handles expired auth user without null assertion', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      expect(source, isNot(contains('state.user!')));
      expect(source, contains("title: 'Session expirée'"));
      expect(source, contains('AuthSessionExpiredRequested'));
    });

    test('consumption failure is blocking dialog and returns to scan', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      expect(source, contains('Future<void> _showFailureDialog'));
      expect(
        source,
        contains(
          "title: technical ? 'Consommation non confirmée' : 'Opération refusée'",
        ),
      );
      expect(source, contains("actionLabel: 'Retour au scan'"));
      expect(source, contains('await _restartScannerAfterModal();'));
    });

    test(
      'successful consumption shows amount datetime transaction and returns home',
      () {
        final source = _read('lib/features/station/screens/scan_screen.dart');

        expect(source, contains('bool _leavingAfterSuccess = false;'));
        expect(
          source,
          contains('setState(() => _leavingAfterSuccess = true);'),
        );
        expect(source, contains('QR consommé avec succès'));
        expect(source, contains('Montant'));
        expect(source, contains('Date/heure'));
        expect(source, contains('N° transaction'));
        expect(source, contains('transaction_name'));
        expect(source, contains('Terminer'));

        final successIndex = source.indexOf('await _showSuccess(');
        expect(successIndex, greaterThanOrEqualTo(0));

        final homeIndex = source.indexOf('_goStationHome();', successIndex);
        expect(homeIndex, greaterThan(successIndex));
      },
    );
    test('scan camera header exposes back arrow to station home', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      expect(
        source,
        contains('_ScanHeader(onBack: _consuming ? null : _goStationHome)'),
      );
      expect(source, contains('return PopScope('));
      expect(source, contains('canPop: !_consuming'));
      expect(source, contains("tooltip: 'Retour à l’accueil'"));
      expect(source, contains('Icons.arrow_back_rounded'));
      expect(source, contains('onPressed: onBack'));
    });
  });
}
