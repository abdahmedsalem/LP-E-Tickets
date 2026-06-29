import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BO-only admin endpoint regression guards', () {
    test('Flutter runtime does not expose BO-only admin mutations', () {
      final violations = _findForbiddenMarkersInLib();

      expect(
        violations,
        isEmpty,
        reason: 'BO-only admin endpoints, methods, routes, or screens must not '
            'be exposed by the Flutter runtime.',
      );
    });

    test('FuelToken admin API surface stays read/positive-validation only', () {
      final configFile =
          File('lib/core/config/odoo_fueltoken_rpc_config.dart');
      expect(configFile.existsSync(), isTrue);

      final config = configFile.readAsStringSync();
      final endpoints = RegExp(
        r'''['"](/api/acpec/fueltoken/v1/admin/[^'"]+)['"]''',
      )
          .allMatches(config)
          .map((match) => match.group(1)!)
          .toSet();

      expect(endpoints, equals(_allowedFuelTokenAdminEndpoints));
    });

    test('Removed BO-only admin screens and routes stay absent', () {
      expect(
        File('lib/features/admin/screens/admin_stations_screen.dart')
            .existsSync(),
        isFalse,
      );
      expect(
        File('lib/features/admin/screens/admin_carnets_screen.dart')
            .existsSync(),
        isFalse,
      );

      final routerFile = File('lib/core/router/app_router.dart');
      expect(routerFile.existsSync(), isTrue);

      final router = routerFile.readAsStringSync();
      for (final marker in _forbiddenAdminUiRouteMarkers) {
        expect(router, isNot(contains(marker)));
      }
    });
  });
}

const _allowedFuelTokenAdminEndpoints = <String>{
  '/api/acpec/fueltoken/v1/admin/purchases/pending',
  '/api/acpec/fueltoken/v1/admin/purchases/detail',
  '/api/acpec/fueltoken/v1/admin/purchases/approve',
  '/api/acpec/fueltoken/v1/admin/stations/list',
  '/api/acpec/fueltoken/v1/admin/reports/summary',
  '/api/acpec/fueltoken/v1/admin/carnet-types/list',
};

const _forbiddenAdminUiRouteMarkers = <String>[
  "path: '/admin/stations'",
  'path: "/admin/stations"',
  "context.go('/admin/stations')",
  'context.go("/admin/stations")',
  "context.push('/admin/stations')",
  'context.push("/admin/stations")',
  "path: '/admin/carnets'",
  'path: "/admin/carnets"',
  "context.go('/admin/carnets')",
  'context.go("/admin/carnets")',
  "context.push('/admin/carnets')",
  'context.push("/admin/carnets")',
];

const _forbiddenRuntimeMarkers = <String>[
  'adminPurchasesReject',
  'adminStationsCreate',
  'adminStationsUpdate',
  'adminStationsDisable',
  'adminCarnetTypesCreate',
  'adminCarnetTypesUpdate',
  'adminCarnetTypesDelete',
  'AdminStationsScreen',
  'AdminCarnetsScreen',
  '/api/acpec/fueltoken/v1/admin/purchases/reject',
  '/api/acpec/fueltoken/v1/admin/stations/create',
  '/api/acpec/fueltoken/v1/admin/stations/update',
  '/api/acpec/fueltoken/v1/admin/stations/disable',
  '/api/acpec/fueltoken/v1/admin/carnet-types/create',
  '/api/acpec/fueltoken/v1/admin/carnet-types/update',
  '/api/acpec/fueltoken/v1/admin/carnet-types/delete',
  ..._forbiddenAdminUiRouteMarkers,
];

List<String> _findForbiddenMarkersInLib() {
  final root = Directory('lib');
  expect(root.existsSync(), isTrue);

  final violations = <String>[];
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final content = file.readAsStringSync();
    for (final marker in _forbiddenRuntimeMarkers) {
      if (content.contains(marker)) {
        violations.add('${file.path}: $marker');
      }
    }
  }

  return violations;
}
