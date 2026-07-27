import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2L2B admin backend unavailable data screens guard', () {
    test(
      'admin home does not show false zero metrics on initial load failure',
      () {
        final source = _read(
          'lib/features/admin/screens/admin_home_screen.dart',
        );

        expect(source, contains('bool _loading = false;'));
        expect(source, contains('_loading && _summary == null'));
        expect(source, contains('_error != null && _summary == null'));
        expect(source, contains('BackendUnavailableBanner'));
        expect(source, contains('ErrorPresenter.backendUnavailable()'));
        expect(source, isNot(contains('OdooJsonRpcException')));
      },
    );

    test('admin reports shows banner when stale summary remains visible', () {
      final source = _read(
        'lib/features/admin/screens/admin_reports_screen.dart',
      );

      expect(source, contains('BackendUnavailableBanner'));
      expect(source, contains('if (_acpecError != null) ...['));
      expect(source, contains('_acpecError != null && _summary == null'));
      expect(source, contains('ErrorPresenter.backendUnavailable()'));
      expect(source, isNot(contains('OdooJsonRpcException')));
    });

    test(
      'admin lots keeps existing list visible with backend warning banner',
      () {
        final source = _read(
          'lib/features/admin/screens/admin_lots_screen.dart',
        );

        expect(source, contains('BackendUnavailableBanner'));
        expect(source, contains('_acpecLots!.isNotEmpty'));
        expect(source, contains('onRetry: _loadAcpecPending'));
        expect(source, contains('ErrorPresenter.backendUnavailable()'));
        expect(source, isNot(contains('OdooJsonRpcException')));
      },
    );

    test(
      'admin submitted purchases keeps existing list visible with backend warning banner',
      () {
        final source = _read(
          'lib/features/admin/screens/admin_submitted_purchases_screen.dart',
        );

        expect(source, contains('BackendUnavailableBanner'));
        expect(source, contains('_acpecLots!.isNotEmpty'));
        expect(source, contains('onRetry: _loadAcpecPending'));
        expect(source, contains('ErrorPresenter.backendUnavailable()'));
        expect(source, isNot(contains('OdooJsonRpcException')));
      },
    );

    test(
      'admin purchase detail remains delegated to purchase detail for Patch2L3',
      () {
        final source = _read(
          'lib/features/admin/screens/admin_purchase_detail_screen.dart',
        );

        expect(source, contains('return PurchaseDetailScreen'));
        expect(source, contains('adminMode: true'));
        expect(source, isNot(contains('BackendUnavailableBanner')));
      },
    );
  });
}
