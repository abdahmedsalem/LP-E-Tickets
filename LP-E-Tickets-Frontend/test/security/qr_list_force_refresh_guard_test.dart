import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QR list force refresh guard', () {
    test('QR list manual refresh invalidates QR list cache variants', () {
      final source = File(
        'lib/features/qr/screens/qr_list_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_refreshLive({bool force = false})'));
      expect(source, contains('_invalidateQrListCache'));
      expect(source, contains('OdooFueltokenRpcConfig.qrList'));
      expect(source, contains("<String, dynamic>{'state': 'active'}"));
      expect(source, contains("<String, dynamic>{'state': 'blocked'}"));
      expect(source, contains("<String, dynamic>{'state': 'consumed'}"));
      expect(source, contains("<String, dynamic>{'state': 'expired'}"));
      expect(source, contains('onRefresh: () => _refreshLive(force: true)'));
    });

    test('QR refresh bus forces a fresh server read', () {
      final source = File(
        'lib/features/qr/screens/qr_list_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_refreshLive(force: true)'));
      expect(source, contains('QrRefreshBus.instance.revision.addListener'));
    });
  });
}
