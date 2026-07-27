import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile platforms use the short public app name', () {
    const displayName = 'LP E-Tickets';
    final sources = <String>[
      'android/app/src/main/AndroidManifest.xml',
      'ios/Runner/Info.plist',
    ];

    for (final path in sources) {
      expect(
        File(path).readAsStringSync(),
        contains(displayName),
        reason: '$path doit contenir le nom public de l’application.',
      );
    }
  });

  test('localizations use the full official app name', () {
    const officialName = 'Leader Petroleum E-Tickets';
    final sources = <String>[
      'lib/l10n/app_fr.arb',
      'lib/l10n/app_ar.arb',
    ];

    for (final path in sources) {
      expect(
        File(path).readAsStringSync(),
        contains(officialName),
        reason: '$path doit contenir le nom officiel de l’application.',
      );
    }
  });
}
