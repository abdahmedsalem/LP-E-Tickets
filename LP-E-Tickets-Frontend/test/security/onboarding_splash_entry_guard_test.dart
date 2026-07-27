import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2H splash entry guard', () {
    test('router starts on splash before deciding onboarding or login', () {
      final router = _read('lib/core/router/app_router.dart');

      expect(router, contains("initialLocation: '/splash'"));
      expect(router, isNot(contains("initialLocation: '/login'")));
      expect(router, contains("path: '/splash'"));
      expect(router, contains("'/splash',"));
      expect(router, contains('const SplashScreen()'));
      expect(router, contains("path: '/language-selection'"));
      expect(router, contains('const LanguageSelectionScreen()'));
      expect(router, contains("path: '/onboarding'"));
      expect(router, contains("path: '/login'"));
    });

    test('android backup is disabled for local onboarding and auth state', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');

      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:fullBackupContent="false"'));
    });
  });
}
