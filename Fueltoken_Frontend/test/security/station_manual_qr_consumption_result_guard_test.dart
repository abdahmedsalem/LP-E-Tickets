import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2QB manual QR consumption result guard', () {
    test(
      'manual station QR use validates backend result before final success dialog',
      () {
        final source = _read(
          'lib/features/station/screens/station_manual_qr_screen.dart',
        );

        final useIndex = source.indexOf('OdooFueltokenFacade().stationQrUse(');
        final guardIndex = source.indexOf(
          'final guarded = acpecRpcMapOrThrow(',
          useIndex,
        );
        final bumpIndex = source.indexOf(
          'ClientHistoryRefreshBus.instance.bump();',
          guardIndex,
        );
        final successIndex = source.indexOf(
          'await _showManualSuccessDialog(',
          bumpIndex,
        );
        final homeIndex = source.indexOf(
          "context.go('/station/home')",
          successIndex,
        );

        expect(useIndex, greaterThanOrEqualTo(0));
        expect(guardIndex, greaterThan(useIndex));
        expect(bumpIndex, greaterThan(guardIndex));
        expect(successIndex, greaterThan(bumpIndex));
        expect(homeIndex, greaterThan(successIndex));

        expect(
          source,
          contains("SensitiveActionIntent.create('station-qr-use')"),
        );
        expect(source, contains('intent.withAuthParams'));
        expect(source, isNot(contains("'idempotency_key': const Uuid().v4()")));
        expect(source, contains('_invalidateStationConsumptionCaches('));

        expect(source, contains('fallbackMessage:'));
        expect(source, contains('publicErrorMessage:'));
        expect(source, contains('transaction_name'));
        expect(source, contains('N° transaction'));

        expect(
          source,
          isNot(contains("_showSnack('QR consommé avec succès.')")),
        );
        expect(source, isNot(contains("context.go('/station/journal')")));
      },
    );
  });
}
