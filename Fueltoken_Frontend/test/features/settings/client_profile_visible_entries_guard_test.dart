import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('client profile hides obsolete theme and service account entries', () {
    final source = File(
      'lib/features/settings/screens/settings_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('l10n.settingsDarkMode')));
    expect(source, isNot(contains('l10n.settingsServiceConnection')));
    expect(source, isNot(contains('l10n.authCreateAnAccount')));
    expect(source, isNot(contains("context.push('/settings/acpec-step1')")));
    expect(source, isNot(contains("context.push('/register')")));
    expect(source, isNot(contains('_darkPref')));
    expect(source, isNot(contains('_persistTheme')));

    expect(source, contains('l10n.settingsLanguage'));
    expect(source, contains('l10n.settingsQuickUnlock'));
    expect(source, contains('_LogoutTile('));
  });
}
