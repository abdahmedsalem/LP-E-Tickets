import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android uses the final Leader Petroleum application identity', () {
    const applicationId = 'com.odoorim.acpec.lp_e_ticket';
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/odoorim/acpec/lp_e_ticket/'
      'MainActivity.kt',
    ).readAsStringSync();

    expect(gradle, contains('namespace = "$applicationId"'));
    expect(gradle, contains('applicationId = "$applicationId"'));
    expect(activity, contains('package $applicationId'));
  });

  test('Android explicitly compiles against and targets API 36', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('compileSdk = 36'));
    expect(gradle, contains('targetSdk = 36'));
  });

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

  test('the app manifest directly declares only required permissions', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final permissions = RegExp(
      r'<uses-permission android:name="([^"]+)"',
    ).allMatches(manifest).map((match) => match.group(1)).toSet();

    expect(
      permissions,
      equals(<String>{
        'android.permission.INTERNET',
        'android.permission.USE_BIOMETRIC',
        'android.permission.CAMERA',
      }),
    );
  });

  test('Android launcher branding uses the Leader Petroleum icon', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final adaptiveIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final sourceIcon = File('assets/images/logo_fueltoken_launcher.png');

    expect(sourceIcon.existsSync(), isTrue);
    expect(
      pubspec,
      contains('image_path: assets/images/logo_fueltoken_launcher.png'),
    );
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(adaptiveIcon, contains('@color/ic_launcher_background'));
    expect(adaptiveIcon, contains('@drawable/ic_launcher_foreground'));
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
