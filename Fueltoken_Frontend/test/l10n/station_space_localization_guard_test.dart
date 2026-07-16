import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/l10n/app_localizations_ar.dart';

void main() {
  test('station screens and dialogs use centralized localization', () {
    final paths = <String>[
      'lib/features/station/screens/station_shell_scaffold.dart',
      'lib/features/station/screens/station_home_screen.dart',
      'lib/features/station/screens/scan_screen.dart',
      'lib/features/station/screens/station_manual_qr_screen.dart',
      'lib/features/station/screens/station_consumption_history_screen.dart',
      'lib/features/station/screens/station_profile_screen.dart',
      'lib/shared/widgets/station_qr_success_dialog.dart',
    ];

    for (final path in paths) {
      expect(
        File(path).readAsStringSync(),
        contains('AppLocalizations'),
        reason: path,
      );
    }
  });

  test('critical station actions are available in Arabic', () {
    final arabic = AppLocalizationsAr();

    expect(arabic.stationNavHome, isNotEmpty);
    expect(arabic.stationScanQr, isNotEmpty);
    expect(arabic.stationManualEntry, isNotEmpty);
    expect(arabic.stationQrNotConsumable, isNotEmpty);
    expect(arabic.stationQrConsumedSuccess, isNotEmpty);
    expect(arabic.stationConsumptionHistory, isNotEmpty);
    expect(arabic.stationProfileTitle, isNotEmpty);
  });
}
