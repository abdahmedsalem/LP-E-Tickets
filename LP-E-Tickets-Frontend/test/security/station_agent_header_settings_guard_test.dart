import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('station agent header settings guard', () {
    test('station home exposes agent identity and profile shortcut', () {
      final source = File(
        'lib/features/station/screens/station_home_screen.dart',
      ).readAsStringSync();

      expect(source, contains('agentName'));
      expect(source, contains('stationAgentFallback'));
      expect(source, contains('stationAgentAtStation'));
      expect(source, contains('Icons.badge_outlined'));
      expect(source, contains('Icons.settings_outlined'));
      expect(source, contains("context.go('/station/profile')"));
      expect(source, isNot(contains("context.go('/settings')")));
      expect(source, isNot(contains("ctx.go('/settings')")));
    });
  });
}
