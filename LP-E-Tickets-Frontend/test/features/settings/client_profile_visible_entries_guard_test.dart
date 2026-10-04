import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('client profile hides obsolete theme and service account entries', () {
    final source = File(
      'lib/features/profile/screens/client_profile_screen.dart',
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
    expect(source, isNot(contains('l10n.settingsPaymentHistory')));
    expect(source, isNot(contains("context.push('/payment-history')")));
    expect(source, contains('l10n.settingsStationsMap'));
    expect(source, contains("context.push('/settings/stations-map')"));
    expect(source, contains('l10n.settingsDeleteAccount'));
    expect(source, contains('_profileController.requestAccountDeletion(pin)'));
    expect(source, contains('_LogoutTile('));
    expect(source, contains('l10n.settingsDevelopedBy'));
    expect(
      source,
      contains('l10n.settingsVersionBuild(_appVersion, _buildNumber)'),
    );
    expect(source, contains('PackageInfo.fromPlatform()'));
  });
}
