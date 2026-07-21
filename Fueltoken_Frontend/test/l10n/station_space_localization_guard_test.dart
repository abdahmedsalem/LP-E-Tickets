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
    expect(arabic.stationFuelConsumption, isNotEmpty);
    expect(arabic.stationQrCode, isNotEmpty);
    expect(arabic.stationTransactionIdentifier, isNotEmpty);
    expect(arabic.stationClientIdentifier, isNotEmpty);
    expect(arabic.stationStationIdentifier, isNotEmpty);
    expect(arabic.stationQrIdentifier, isNotEmpty);
    expect(arabic.stationLotIdentifier, isNotEmpty);
    expect(arabic.stationOperatorIdentifier, isNotEmpty);
    expect(arabic.stationManualExample, isNotEmpty);
  });

  test('station history has no remaining hardcoded French UI labels', () {
    final source = File(
      'lib/features/station/screens/station_consumption_history_screen.dart',
    ).readAsStringSync();
    const forbiddenLabels = <String>[
      'Consommation de carburant',
      'Client inconnu',
      'Station inconnue',
      'N° transaction',
      'Code QR',
      'Consommation station',
      'Détail de la consommation',
      'Réessayer',
    ];

    for (final label in forbiddenLabels) {
      expect(source, isNot(contains("'$label'")), reason: label);
    }
  });

  test('station errors never bypass localized user messages', () {
    final paths = <String>[
      'lib/features/station/screens/scan_screen.dart',
      'lib/features/station/screens/station_manual_qr_screen.dart',
      'lib/features/station/screens/station_consumption_history_screen.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('Localizations.localeOf(context).languageCode')),
        reason: '$path must use AppLocalizations for user messages',
      );
      expect(
        source,
        isNot(contains('ErrorPresenter.backendUnavailable()')),
        reason: '$path must localize backend availability errors',
      );
    }
  });
}
