import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('device security anchor guard', () {
    test(
      'router anchors pending and blocked device states to security screen',
      () {
        final source = File(
          'lib/core/router/app_router.dart',
        ).readAsStringSync();

        expect(source, contains('deviceSecurityRestricted'));
        expect(source, contains('isDeviceActivationPending'));
        expect(source, contains('isDeviceBlocked'));
        expect(source, contains("return '/activation-pending'"));
      },
    );

    test('activation pending screen adapts copy for blocked devices', () {
      final source = File(
        'lib/features/auth/screens/activation_pending_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('final deviceBlocked = user?.isDeviceBlocked == true;'),
      );
      expect(source, contains('Appareil bloqué'));
      expect(source, contains('Contactez l’administrateur'));
      expect(source, contains('Vérifier à nouveau'));
      expect(source, contains('Activation en attente'));
    });

    test('session business auth codes stay strict and backend-confirmed', () {
      final source = File(
        'lib/data/services/odoo_jsonrpc_client.dart',
      ).readAsStringSync();

      expect(source, contains("code == 'AUTH_REQUIRED'"));
      expect(source, contains("code == 'SESSION_EXPIRED'"));
      expect(source, contains("code == 'REFRESH_TOKEN_REQUIRED'"));
      expect(source, isNot(contains("code == 'UNAUTHORIZED'")));
      expect(source, isNot(contains("code == 'TOKEN_EXPIRED'")));
    });
  });
}
