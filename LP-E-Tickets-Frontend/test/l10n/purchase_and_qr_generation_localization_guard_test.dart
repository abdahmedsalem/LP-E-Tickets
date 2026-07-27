import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/l10n/app_localizations_ar.dart';

void main() {
  test('purchase and QR generation terminology is available in Arabic', () {
    final arabic = AppLocalizationsAr();
    expect(arabic.purchaseOrderTitle, 'طلب دفاتر');
    expect(arabic.purchaseConfirmTitle, 'تأكيد الطلب');
    expect(arabic.purchaseSuccessTitle, 'تم تسجيل طلب الدفاتر');
    expect(arabic.qrGenerationTitle, 'إنشاء QR');
    expect(arabic.qrGenerationConfirmTitle, 'تأكيد إنشاء QR');
    expect(arabic.qrGeneratedTitle, 'تم إنشاء QR');
  });

  test('purchase and QR generation flow screens use AppLocalizations', () {
    final paths = <String>[
      'lib/features/purchases/screens/submit_purchase_screen.dart',
      'lib/features/purchases/screens/purchase_confirmation_screen.dart',
      'lib/features/purchases/screens/purchase_detail_screen.dart',
      'lib/features/qr/screens/emit_qr_screen.dart',
      'lib/shared/widgets/purchase_submit_success_dialog.dart',
      'lib/shared/widgets/qr_generation_carnet_line.dart',
    ];
    for (final path in paths) {
      expect(
        File(path).readAsStringSync(),
        contains('AppLocalizations'),
        reason: path,
      );
    }
  });
}
