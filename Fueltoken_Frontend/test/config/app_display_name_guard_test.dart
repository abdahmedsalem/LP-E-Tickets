import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile platforms and localizations share the public app name', () {
    const displayName = 'Leader Petroleum Tickets';
    final sources = <String>[
      'android/app/src/main/AndroidManifest.xml',
      'ios/Runner/Info.plist',
      'lib/l10n/app_fr.arb',
      'lib/l10n/app_ar.arb',
    ];

    for (final path in sources) {
      expect(
        File(path).readAsStringSync(),
        contains(displayName),
        reason: '$path doit contenir le nom public de l’application.',
      );
    }
  });
}
