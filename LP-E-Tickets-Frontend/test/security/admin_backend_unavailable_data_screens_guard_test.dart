import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Admin frontend removal guard', () {
    test('admin frontend screens are removed from the Flutter tree', () {
      const removedFiles = <String>[
        'lib/features/admin/screens/admin_home_screen.dart',
        'lib/features/admin/screens/admin_lots_screen.dart',
        'lib/features/admin/screens/admin_more_screen.dart',
        'lib/features/admin/screens/admin_profile_screen.dart',
        'lib/features/admin/screens/admin_purchase_detail_screen.dart',
        'lib/features/admin/screens/admin_reports_screen.dart',
        'lib/features/admin/screens/admin_shell_scaffold.dart',
        'lib/features/admin/screens/admin_submitted_purchases_screen.dart',
      ];

      for (final path in removedFiles) {
        expect(
          File(path).existsSync(),
          isFalse,
          reason: '$path should no longer exist in the frontend',
        );
      }
    });

    test('router no longer exposes admin shell screens', () {
      final router = _read('lib/core/router/app_router.dart');

      expect(router, isNot(contains('AdminShellScaffold')));
      expect(router, isNot(contains('AdminHomeScreen')));
      expect(router, isNot(contains('AdminSubmittedPurchasesScreen')));
      expect(router, isNot(contains('AdminProfileScreen')));
      expect(router, isNot(contains('AdminMoreScreen')));
      expect(router, isNot(contains('AdminLotsScreen')));
      expect(router, isNot(contains('AdminReportsScreen')));
      expect(router, isNot(contains('AdminPurchaseDetailScreen')));
      expect(router, isNot(contains("path: '/admin/achats'")));
      expect(router, isNot(contains("path: '/admin/profile'")));
      expect(router, isNot(contains("path: '/admin/more'")));
      expect(router, isNot(contains("path: '/admin/lots'")));
      expect(router, isNot(contains("path: '/admin/purchases/:id'")));
      expect(router, isNot(contains("path: '/admin/reports'")));
    });
  });
}
