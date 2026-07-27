import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Flutter remaining endpoint allowlist guard', () {
    test('all Flutter /api/acpec endpoints are explicitly allowed', () {
      final discovered = _discoverAcpecEndpointsInLib();

      expect(
        discovered,
        equals(_allowedFlutterAcpecEndpoints),
        reason:
            'Every Flutter /api/acpec endpoint must be explicitly '
            'reviewed and listed in this test.',
      );
    });

    test(
      'known BO/provisioning-only endpoints stay absent from Flutter lib',
      () {
        final discovered = _discoverAcpecEndpointsInLib();
        final forbidden = discovered.intersection(
          _forbiddenFlutterRuntimeEndpoints,
        );

        expect(
          forbidden,
          isEmpty,
          reason:
              'BO-only or provisioning-only endpoints must not be exposed '
              'by the Flutter runtime.',
        );
      },
    );
  });
}

const _allowedFlutterAcpecEndpoints = <String>{
  // Mobile Auth runtime.
  '/api/acpec/mobile_auth/v1/login',
  '/api/acpec/mobile_auth/v1/session-check',
  '/api/acpec/mobile_auth/v1/confirm-pin',
  '/api/acpec/mobile_auth/v1/logout',
  '/api/acpec/mobile_auth/v1/refresh',
  '/api/acpec/mobile_auth/v1/me',
  '/api/acpec/mobile_auth/v1/signup',
  '/api/acpec/mobile_auth/v1/request-otp',
  '/api/acpec/mobile_auth/v1/verify-otp',
  '/api/acpec/mobile_auth/v1/version-check',
  '/api/acpec/mobile_auth/v1/signup-companies',

  // FuelToken client mobile.
  '/api/acpec/fueltoken/v1/mobile/wallet/current',
  '/api/acpec/fueltoken/v1/mobile/transactions',
  '/api/acpec/fueltoken/v1/mobile/transactions/detail',
  '/api/acpec/fueltoken/v1/mobile/purchases/create',
  '/api/acpec/fueltoken/v1/mobile/purchases',
  '/api/acpec/fueltoken/v1/mobile/purchases/detail',
  '/api/acpec/fueltoken/v1/mobile/faces',
  '/api/acpec/fueltoken/v1/mobile/carnet-types',
  '/api/acpec/fueltoken/v1/mobile/qr/issue',
  '/api/acpec/fueltoken/v1/mobile/qr/list',
  '/api/acpec/fueltoken/v1/mobile/qr/detail',
  '/api/acpec/fueltoken/v1/mobile/qr/retirer',
  '/api/acpec/fueltoken/v1/mobile/qr/separer',
  '/api/acpec/fueltoken/v1/mobile/carnets/transfer',
  '/api/acpec/fueltoken/v1/mobile/carnets/transfer/recipient',
  '/api/acpec/fueltoken/v1/mobile/tickets/transfer',

  // Station mobile.
  '/api/acpec/fueltoken/v1/mobile/qr/reveal-code',
  '/api/acpec/fueltoken/v1/station/qr/use',
  '/api/acpec/fueltoken/v1/station/transactions',
  '/api/acpec/fueltoken/v1/station/profile',
  '/api/acpec/fueltoken/v1/station/qr/check',

  // Manager mobile: read + positive validation only.
  '/api/acpec/fueltoken/v1/admin/purchases/pending',
  '/api/acpec/fueltoken/v1/admin/purchases/detail',
  '/api/acpec/fueltoken/v1/admin/purchases/approve',

  // Read-only admin support still consumed by mobile dashboards/catalogues.
  '/api/acpec/fueltoken/v1/admin/stations/list',
  '/api/acpec/fueltoken/v1/admin/reports/summary',
  '/api/acpec/fueltoken/v1/admin/carnet-types/list',
};

const _forbiddenFlutterRuntimeEndpoints = <String>{
  // FuelToken BO-only mutations.
  '/api/acpec/fueltoken/v1/admin/purchases/reject',
  '/api/acpec/fueltoken/v1/admin/stations/create',
  '/api/acpec/fueltoken/v1/admin/stations/update',
  '/api/acpec/fueltoken/v1/admin/stations/disable',
  '/api/acpec/fueltoken/v1/admin/carnet-types/create',
  '/api/acpec/fueltoken/v1/admin/carnet-types/update',
  '/api/acpec/fueltoken/v1/admin/carnet-types/delete',

  // Mobile Auth provisioning/BO audit endpoints.
  '/api/acpec/mobile_auth/v1/admin/account-requests',
};

Set<String> _discoverAcpecEndpointsInLib() {
  final root = Directory('lib');
  expect(root.existsSync(), isTrue);

  final endpointPattern = RegExp(r'/api/acpec/[A-Za-z0-9_./:-]+');
  final endpoints = <String>{};
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final content = file.readAsStringSync();
    for (final match in endpointPattern.allMatches(content)) {
      final endpoint = match.group(0)!;
      if (_isDocumentationPlaceholder(endpoint)) continue;
      endpoints.add(endpoint);
    }
  }

  return endpoints;
}

bool _isDocumentationPlaceholder(String endpoint) {
  return endpoint.contains('...') || endpoint.contains('…');
}
