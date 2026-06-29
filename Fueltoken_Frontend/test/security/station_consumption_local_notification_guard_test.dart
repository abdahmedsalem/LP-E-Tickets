import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('station consumption local notification guard', () {
    test('local notification service covers station consumption', () {
      final source = File(
        'lib/core/notifications/purchase_validation_notification_service.dart',
      ).readAsStringSync();

      expect(source, contains('_syncStationConsumptionNotifications'));
      expect(source, contains('_stationConsumptionPrefsPrefix'));
      expect(source, contains('_hasNotifiedIds'));
      expect(source, contains('emitNew: stationPrefsInitialized'));
      expect(source, contains('if (!emitNew)'));
      expect(source, contains('_emitStationConsumptionNotification'));
      expect(source, contains('_buildStationConsumptionNotification'));
      expect(source, contains('_loadStationConsumptionTransactions'));
      expect(source, contains('TxType.stationConsumption'));
      expect(source, contains("category: 'station_consumption'"));
      expect(source, contains("return 'station-consumption-\${tx.id}'"));
    });

    test(
      'station consumption notification displays QR numeric code when resolvable',
      () {
        final source = File(
          'lib/core/notifications/purchase_validation_notification_service.dart',
        ).readAsStringSync();

        expect(source, contains('_resolveQrNumericCodeForTransaction'));
        expect(source, contains('OdooFueltokenFacade().qrDetail'));
        expect(source, contains('AcpecQrMapper.detailParamsForRouteId'));
        expect(source, contains('AcpecQrMapper.fromRpcEnvelope'));
        expect(source, contains('qr.qrNumericCode'));
        expect(source, contains('_formatQrNumericCode'));
        expect(source, contains("QR \$qrCode consommé"));
        expect(source, contains('digits.length != 12'));
        expect(source, contains('substring(0, 4)'));
        expect(source, contains('substring(4, 8)'));
        expect(source, contains('substring(8, 12)'));
      },
    );

    test('app resume triggers notification sync for user role', () {
      final source = File('lib/main.dart').readAsStringSync();

      expect(source, contains('didChangeAppLifecycleState'));
      expect(source, contains('AppLifecycleState.resumed'));
      expect(
        source,
        contains('PurchaseValidationNotificationService.instance.syncForUser'),
      );
      expect(source, contains('currentUser.role == UserRole.user'));
    });

    test('Firebase push remains explicitly V2, not V1 runtime dependency', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final note = File(
        'AUDIT_FLUTTER_NOTIFICATION_SCOPE.md',
      ).readAsStringSync();

      expect(pubspec, isNot(contains('firebase_messaging')));
      expect(pubspec, isNot(contains('firebase_core')));
      expect(note, contains('V2 — Firebase / Google push notifications'));
      expect(note, contains('Firebase Cloud Messaging'));
      expect(note, contains('Never block station consumption'));
    });
  });
}
