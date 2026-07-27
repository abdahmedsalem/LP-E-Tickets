import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QR issue refresh cache guard', () {
    test('QR issue invalidates all QR list cache variants before refresh bus', () {
      final source = File(
        'lib/features/qr/screens/emit_qr_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_refreshClientReadModelsAfterQrIssue'));
      expect(source, contains("<String, dynamic>{'state': 'active'}"));
      expect(source, contains("<String, dynamic>{'state': 'blocked'}"));
      expect(source, contains("<String, dynamic>{'state': 'consumed'}"));
      expect(source, contains("<String, dynamic>{'state': 'expired'}"));

      final activeIndex = source.indexOf("<String, dynamic>{'state': 'active'}");
      final busIndex = source.indexOf('QrRefreshBus.instance.bump();');
      expect(activeIndex, greaterThan(-1));
      expect(busIndex, greaterThan(-1));
      expect(activeIndex, lessThan(busIndex));
    });

    test('QR issue still refreshes wallet, faces and client history', () {
      final source = File(
        'lib/features/qr/screens/emit_qr_screen.dart',
      ).readAsStringSync();

      expect(source, contains('FacesRefreshBus.instance.bump();'));
      expect(source, contains('WalletRefreshBus.instance.bump();'));
      expect(source, contains('ClientHistoryRefreshBus.instance.bump();'));
      expect(source, contains('OdooFueltokenRpcConfig.faces'));
      expect(source, contains('OdooFueltokenRpcConfig.transactions'));
    });
  });
}
