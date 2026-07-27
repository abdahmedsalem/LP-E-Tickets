import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2S station client route guard', () {
    test('station user is redirected away from client mobile-only paths', () {
      final source = _read('lib/core/router/app_router.dart');

      expect(
        source,
        contains("role == UserRole.station && _isClientAppPath(loc)"),
      );
      expect(source, contains("return '/station/home';"));

      final stationTransactions = source.indexOf(
        "role == UserRole.station && loc == '/transactions'",
      );
      final stationClientGuard = source.indexOf(
        "role == UserRole.station && _isClientAppPath(loc)",
      );

      expect(stationTransactions, greaterThanOrEqualTo(0));
      expect(stationClientGuard, greaterThan(stationTransactions));
      expect(
        source.indexOf("return '/station/journal';", stationTransactions),
        lessThan(stationClientGuard),
      );
    });

    test('client path classifier covers purchase, QR and transfer screens', () {
      final source = _read('lib/core/router/app_router.dart');

      expect(source, contains("loc == '/home'"));
      expect(source, contains("loc == '/faces'"));
      expect(source, contains("loc == '/transactions'"));
      expect(source, contains("loc.startsWith('/purchases')"));
      expect(source, contains("loc.startsWith('/transfer-')"));
      expect(source, contains("loc.startsWith('/qr')"));
      expect(source, contains("loc.startsWith('/wallet')"));
      expect(source, contains("loc.startsWith('/settings')"));
      expect(source, contains("loc == '/notifications'"));
    });

    test('station routes remain available to station users', () {
      final source = _read('lib/core/router/app_router.dart');

      expect(source, contains("path: '/station/home'"));
      expect(source, contains("path: '/station/scan'"));
      expect(source, contains("path: '/station/manual'"));
      expect(source, contains("path: '/station/journal'"));
      expect(source, contains("path: '/station/profile'"));
      expect(
        source,
        contains("path: '/station', redirect: (_, _) => '/station/home'"),
      );
    });
  });
}
