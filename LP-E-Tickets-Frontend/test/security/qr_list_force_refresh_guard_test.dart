import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QR list force refresh guard', () {
    test('QR list manual refresh invalidates every paginated cache entry', () {
      final source = File(
        'lib/features/portfolio/screens/qr_list_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_refreshLive({bool force = false})'));
      expect(source, contains('_invalidateQrListCache'));
      final repository = File(
        'lib/data/repositories/portfolio_repository.dart',
      ).readAsStringSync();
      expect(source, contains('_controller.invalidateQrs'));
      expect(repository, contains('OdooFueltokenRpcConfig.qrList'));
      expect(repository, contains('invalidateRoute('));
      expect(repository, contains('OdooFueltokenRpcConfig.qrList'));
      expect(source, contains('onRefresh: () => _refreshLive(force: true)'));
    });

    test('QR refresh bus forces a fresh server read', () {
      final source = File(
        'lib/features/portfolio/screens/qr_list_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_refreshLive(force: true)'));
      expect(source, contains('QrRefreshBus.instance.revision.addListener'));
    });
  });
}
