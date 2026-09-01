import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';

void main() {
  test('home translations are available in French and Arabic', () {
    final french = lookupAppLocalizations(const Locale('fr'));
    final arabic = lookupAppLocalizations(const Locale('ar'));

    expect(french.homeQuickActions, 'Actions rapides');
    expect(arabic.homeQuickActions, 'إجراءات سريعة');
    expect(arabic.homeVerifiedAccount, 'حساب موثّق');
    expect(arabic.homeBuyCarnets, 'طلب الدفاتر');
    expect(arabic.homeGenerateQr, 'إنشاء رمز QR');
    expect(arabic.homeTransferCarnets, 'تحويل الدفاتر');
    expect(arabic.homeTransferTickets, 'تحويل التذاكر');
    expect(arabic.commonRetry, 'إعادة المحاولة');
    expect(arabic.navHome, 'الرئيسية');
    expect(french.navWallet, 'Opérations');
    expect(french.navPortfolio, 'Portefeuille');
    expect(arabic.navWallet, 'العمليات');
    expect(arabic.navPortfolio, 'المحفظة');
    expect(arabic.navHistory, 'السجل');
  });
}
