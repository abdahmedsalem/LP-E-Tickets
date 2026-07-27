import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('station consumption local notification guard', () {
    test(
      'station consumption notification never resolves or displays manual QR code',
      () {
        final source = File(
          'lib/core/notifications/purchase_validation_notification_service.dart',
        ).readAsStringSync();

        expect(source, isNot(contains('OdooFueltokenFacade().qrDetail')));
        expect(source, isNot(contains('_formatQrNumericCode')));
        expect(source, isNot(contains('_resolveQrNumericCodeForTransaction')));
        expect(source, isNot(contains(r'QR $qrCode consomm')));
        expect(source, contains("final title = 'QR consomm"));
        expect(source, contains("category: 'station_consumption'"));
        expect(source, contains("qrPublicCode: tx.qrPublicCode"));
      },
    );
  });
}
