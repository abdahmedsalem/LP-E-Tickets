import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2L2A backend unavailable data screens guard', () {
    test('shared backend unavailable banner exists', () {
      final source = _read('lib/shared/widgets/backend_unavailable_banner.dart');

      expect(source, contains('class BackendUnavailableBanner'));
      expect(source, contains('Icons.cloud_off_rounded'));
      expect(source, contains('Réessayer'));
    });

    test('QR list preserves existing data and does not show false empty state', () {
      final source = _read('lib/features/qr/screens/qr_list_screen.dart');

      expect(source, contains('BackendUnavailableBanner'));
      expect(source, contains('Erreur de chargement'));
      expect(
        source,
        isNot(
          contains(
            "_liveError = e.toString().replaceFirst('Exception: ', '');\n"
            "        _liveQrs = [];",
          ),
        ),
      );
      expect(source, contains('ErrorPresenter.backendUnavailable()'));
    });

    test('purchases list preserves lots and shows warning banner over cached list', () {
      final source = _read('lib/features/purchases/screens/purchases_list_screen.dart');

      expect(source, contains('BackendUnavailableBanner'));
      expect(source, contains('_error != null && _lots.isEmpty'));
      expect(source, contains('_lots.length + (_error != null ? 1 : 0)'));
      expect(source, isNot(contains("_error = e.toString().replaceFirst('Exception: ', '');\n          _lots = [];")));
    });

    test('carnets screen shows backend warning when old carnets remain visible', () {
      final source = _read('lib/features/home/screens/faces_detail_screen.dart');

      expect(source, contains('BackendUnavailableBanner'));
      expect(source, contains('_liveError != null && allLines.isNotEmpty'));
      expect(source, contains('ErrorPresenter.message(e)'));
    });

    test('transactions preserve history on refresh failure', () {
      final source = _read('lib/features/transactions/screens/transactions_screen.dart');

      expect(source, contains('BackendUnavailableBanner'));
      expect(source, contains('ErrorPresenter.backendUnavailable()'));
      expect(source, isNot(contains('if (reset) _acpecItems = [];')));
      expect(source, contains('groupIndex'));
    });

    test('station consumption history preserves existing rows on backend failure', () {
      final source = _read(
        'lib/features/station/screens/station_consumption_history_screen.dart',
      );

      expect(source, contains('BackendUnavailableBanner'));
      expect(source, contains('_error != null && _items.isNotEmpty'));
      expect(
        source,
        isNot(
          contains(
            "_error = _briefError(e);\n"
            "        _items = [];\n"
            "        _loading = false;",
          ),
        ),
      );
      expect(source, contains('ErrorPresenter.backendUnavailable()'));
    });
  });
}
