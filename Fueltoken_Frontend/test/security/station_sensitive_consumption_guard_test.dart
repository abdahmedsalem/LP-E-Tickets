import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2R station sensitive consumption guard', () {
    test(
      'scan consumption uses sensitive intent and prudent backend error',
      () {
        final source = _read('lib/features/station/screens/scan_screen.dart');

        expect(source, contains("_unconfirmedConsumptionMessage"));
        expect(source, contains("Vérifiez l’historique avant de réessayer"));
        expect(
          source,
          contains("SensitiveActionIntent.create('station-qr-use')"),
        );
        expect(source, contains('intent.withAuthParams'));
        expect(source, isNot(contains("'idempotency_key': const Uuid().v4()")));
        expect(source, contains("ErrorPresenter.isBackendUnavailable"));
        expect(source, contains("ErrorPresenter.message"));
        expect(
          source,
          isNot(contains("err.toString().replaceFirst('Exception: ', '')")),
        );
      },
    );

    test('scan consumption is locked before station PIN dialog', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      final consumeIndex = source.indexOf('Future<void> _consume(String code)');
      final lockIndex = source.indexOf(
        'setState(() => _consuming = true);',
        consumeIndex,
      );
      final pinIndex = source.indexOf(
        'showSensitiveActionCodeDialog',
        consumeIndex,
      );

      expect(consumeIndex, greaterThanOrEqualTo(0));
      expect(lockIndex, greaterThanOrEqualTo(0));
      expect(pinIndex, greaterThanOrEqualTo(0));
      expect(lockIndex, lessThan(pinIndex));
    });

    test('manual consumption locks before PIN dialog', () {
      final source = _read(
        'lib/features/station/screens/station_manual_qr_screen.dart',
      );

      final consumeIndex = source.indexOf('Future<void> _consumeManualCode()');
      final lockIndex = source.indexOf(
        'setState(() => _consuming = true);',
        consumeIndex,
      );
      final pinIndex = source.indexOf(
        'showSensitiveActionCodeDialog',
        consumeIndex,
      );

      expect(consumeIndex, greaterThanOrEqualTo(0));
      expect(lockIndex, greaterThanOrEqualTo(0));
      expect(pinIndex, greaterThanOrEqualTo(0));
      expect(lockIndex, lessThan(pinIndex));
    });

    test(
      'manual check refusal uses QR non consommable dialog, not snackbar',
      () {
        final source = _read(
          'lib/features/station/screens/station_manual_qr_screen.dart',
        );

        expect(
          source,
          contains('final result = StationQrCheckResult.fromRpc(raw);'),
        );
        expect(source, contains('if (!result.canConsume)'));
        expect(source, contains("title: 'QR non consommable'"));
        expect(source, contains("actionLabel: 'Retour à l’accueil'"));
        expect(source, contains("context.go('/station/home')"));
        expect(
          source,
          isNot(contains('_showSnack(_errorMessage(e), error: true);')),
        );
      },
    );

    test('manual action errors are prudent and stay on manual entry', () {
      final source = _read(
        'lib/features/station/screens/station_manual_qr_screen.dart',
      );

      expect(
        source,
        contains("SensitiveActionIntent.create('station-qr-use')"),
      );
      expect(source, contains('intent.withAuthParams'));
      expect(source, contains('_invalidateStationConsumptionCaches('));
      expect(source, contains('Future<void> _showManualFailureDialog'));
      expect(source, contains('ErrorPresenter.isBackendUnavailable'));
      expect(source, contains("_unconfirmedConsumptionMessage"));
      expect(source, contains("_sensitiveActionErrorMessage"));
      expect(
        source,
        contains(
          "title: technical ? 'Consommation non confirmée' : 'Opération refusée'",
        ),
      );
      expect(source, contains("actionLabel: 'Retour à la saisie'"));
    });
  });
}
