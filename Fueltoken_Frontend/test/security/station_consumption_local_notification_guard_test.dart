import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('station consumption local notification guard', () {
    test(
      'station consumption notification does not resolve manual QR code through qrDetail',
      () {
        final source = File(
          'lib/core/notifications/purchase_validation_notification_service.dart',
        ).readAsStringSync();

        expect(source, isNot(contains('OdooFueltokenFacade().qrDetail')));
        expect(
          source,
          isNot(contains('return _formatQrNumericCode(qr.qrNumericCode)')),
        );
        expect(
          source,
          contains('résolution automatique du code manuel QR désactivée'),
        );
      },
    );
  });
}
