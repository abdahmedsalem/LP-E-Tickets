import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2L3B station sensitive consumption guard', () {
    test('scan consumption uses idempotency key and prudent backend error', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      expect(source, contains("_unconfirmedConsumptionMessage"));
      expect(source, contains("Vérifiez l’historique avant de réessayer"));
      expect(source, contains("'idempotency_key': const Uuid().v4()"));
      expect(source, contains("ErrorPresenter.isBackendUnavailable(err)"));
      expect(source, contains("ErrorPresenter.message(err)"));
      expect(
        source,
        isNot(contains("err.toString().replaceFirst('Exception: ', '')")),
      );
    });

    test('scan consumption is locked before station PIN dialog', () {
      final source = _read('lib/features/station/screens/scan_screen.dart');

      final consumeIndex = source.indexOf('Future<void> _consume(String code)');
      final lockIndex = source.indexOf(
        'setState(() => _consuming = true);',
        consumeIndex,
      );
      final pinIndex = source.indexOf('showSensitiveActionCodeDialog', consumeIndex);

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
      final pinIndex = source.indexOf('showSensitiveActionCodeDialog', consumeIndex);

      expect(consumeIndex, greaterThanOrEqualTo(0));
      expect(lockIndex, greaterThanOrEqualTo(0));
      expect(pinIndex, greaterThanOrEqualTo(0));
      expect(lockIndex, lessThan(pinIndex));
    });

    test('manual consumption keeps check errors normal but action errors prudent', () {
      final source = _read(
        'lib/features/station/screens/station_manual_qr_screen.dart',
      );

      expect(source, contains('_showSnack(_errorMessage(e), error: true);'));
      expect(
        source,
        contains('_showSnack(_sensitiveActionErrorMessage(e), error: true);'),
      );
      expect(source, contains('ErrorPresenter.isBackendUnavailable(error)'));
      expect(source, contains("_unconfirmedConsumptionMessage"));
      expect(source, isNot(contains('OdooJsonRpcException')));
    });
  });
}
