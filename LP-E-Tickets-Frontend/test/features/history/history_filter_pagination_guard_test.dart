import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'client history uses complete calendar days and raw API page offsets',
    () {
      final source = File(
        'lib/features/history/screens/transactions_screen.dart',
      ).readAsStringSync();
      expect(source, contains("_apiDateTime(_startOfDay(_activeFrom))"));
      expect(source, contains("_apiDateTime(_endOfDay(_activeTo))"));
      expect(source, contains('final offset = reset ? 0 : _nextAcpecOffset;'));
      expect(
        source,
        contains('_nextAcpecOffset = offset + page.items.length;'),
      );
      expect(source, contains('_reloadAcpecForCurrentFilter();'));
    },
  );

  test(
    'station history sends date range to backend and reloads on filter change',
    () {
      final source = File(
        'lib/features/station/historique_consommation/station_consumption_history_screen.dart',
      ).readAsStringSync();
      expect(
        source,
        contains("'date_from': _apiDateTime(_dayStart(_activeFrom))"),
      );
      expect(source, contains("'date_to': _apiDateTime(_dayEnd(_activeTo))"));
      expect(source, contains('void _applyFilter(DateTimeRange range)'));
      expect(source, contains('      _load();'));
      expect(source, contains('_load(reset: false)'));
    },
  );
}
