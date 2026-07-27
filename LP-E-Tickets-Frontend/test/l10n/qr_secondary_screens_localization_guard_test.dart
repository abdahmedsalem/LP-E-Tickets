import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/l10n/app_localizations_ar.dart';

void main() {
  test('QR secondary screens expose natural Arabic terminology', () {
    final arabic = AppLocalizationsAr();

    expect(arabic.qrDetailTitle, 'تفاصيل QR');
    expect(arabic.qrWithdrawTitle, 'سحب تذاكر');
    expect(arabic.qrSeparateTitle, 'فصل التذاكر الصالحة');
    expect(arabic.qrManualCode, 'الرمز اليدوي');
    expect(arabic.commonPinVerification, 'التحقق من الرقم السري');
    expect(arabic.validTickets, 'التذاكر الصالحة');
  });

  test('QR detail, withdrawal and separation use localization resources', () {
    final paths = <String>[
      'lib/features/qr/screens/qr_detail_screen.dart',
      'lib/features/qr/screens/retirer_qr_screen.dart',
      'lib/features/qr/screens/separer_qr_screen.dart',
      'lib/features/qr/screens/qr_action_confirmation_screen.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, contains('AppLocalizations.of(context)'), reason: path);
    }

    final detail = File(paths[0]).readAsStringSync();
    final withdrawal = File(paths[1]).readAsStringSync();
    final separation = File(paths[2]).readAsStringSync();

    expect(detail, contains('l10n.qrDetailTitle'));
    expect(detail, contains('SingleLineCardTitle('));
    expect(withdrawal, contains('l10n.selectedLines(selectedLineCount)'));
    expect(separation, contains('l10n.qrSeparationDisclaimer'));
  });

  test('localized screens use centralized localized error presentation', () {
    final paths = <String>[
      'lib/features/home/screens/faces_detail_screen.dart',
      'lib/features/qr/screens/qr_list_screen.dart',
      'lib/features/transactions/screens/transactions_screen.dart',
      'lib/features/qr/screens/qr_detail_screen.dart',
      'lib/features/qr/screens/retirer_qr_screen.dart',
      'lib/features/qr/screens/separer_qr_screen.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('ErrorPresenter.localizedMessage(context, e)'),
        reason: path,
      );
    }
  });
}
