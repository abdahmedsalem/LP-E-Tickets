import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2QB manual QR consumption result guard', () {
    test(
      'manual station QR use validates backend result before final success dialog',
      () {
        final source = _read(
          'lib/features/station/scan/station_manual_qr_screen.dart',
        );
        final dialogSource = _read(
          'lib/shared/widgets/station_qr_success_dialog.dart',
        );
        final controller = _read(
          'lib/features/station/controllers/station_controller.dart',
        );
        final repository = _read(
          'lib/data/repositories/station_repository.dart',
        );

        final useIndex = source.indexOf('_stationController.consumeQr(');
        final guardIndex = repository.indexOf(
          'final result = acpecRpcMapOrThrow(',
        );
        final bumpIndex = source.indexOf(
          'ClientHistoryRefreshBus.instance.bump();',
          useIndex,
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
        expect(guardIndex, greaterThanOrEqualTo(0));
        expect(bumpIndex, greaterThan(useIndex));
        expect(successIndex, greaterThan(bumpIndex));
        expect(homeIndex, greaterThan(successIndex));

        expect(controller, contains('station-qr-use'));
        expect(controller, contains('withAuthParams('));
        expect(source, isNot(contains("'idempotency_key': const Uuid().v4()")));
        expect(repository, contains('_invalidateConsumptionCaches(routeCode)'));

        expect(repository, contains('fallbackMessage:'));
        expect(repository, contains('publicErrorMessage:'));
        expect(repository, contains('transaction_name'));
        expect(source, contains('StationQrSuccessDialog('));
        expect(dialogSource, contains('stationTransactionNumber'));

        expect(
          source,
          isNot(contains("_showSnack('QR consommé avec succès.')")),
        );
        expect(source, isNot(contains("context.go('/station/journal')")));
      },
    );
  });
}
