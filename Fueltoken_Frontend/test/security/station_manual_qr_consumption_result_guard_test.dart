import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2QB manual QR consumption result guard', () {
    test('manual station QR use validates backend result before success', () {
      final source = _read(
        'lib/features/station/screens/station_manual_qr_screen.dart',
      );

      final useIndex = source.indexOf('stationQrUse(payload)');
      final guardIndex = source.indexOf('acpecRpcMapOrThrow(', useIndex);
      final bumpIndex = source.indexOf(
        'ClientHistoryRefreshBus.instance.bump();',
        useIndex,
      );
      final successIndex = source.indexOf(
        "_showSnack('QR consommé avec succès.');",
        useIndex,
      );

      expect(
        source,
        contains(
          "import '../../../data/services/acpec_rpc_result_guard.dart';",
        ),
      );
      expect(useIndex, greaterThanOrEqualTo(0));
      expect(guardIndex, greaterThan(useIndex));
      expect(bumpIndex, greaterThan(guardIndex));
      expect(successIndex, greaterThan(guardIndex));

      expect(source, contains('Consommation QR refusée par le serveur.'));
      expect(
        source,
        contains(
          'La consommation du QR a échoué. Réessayez ou contactez l’administrateur.',
        ),
      );
    });

    test(
      'manual station QR no longer bumps or succeeds immediately after rpc call',
      () {
        final source = _read(
          'lib/features/station/screens/station_manual_qr_screen.dart',
        );

        expect(
          source,
          isNot(
            contains(
              'await OdooFueltokenFacade().stationQrUse(payload);\n'
              '      ClientHistoryRefreshBus.instance.bump();',
            ),
          ),
        );
      },
    );
  });
}
