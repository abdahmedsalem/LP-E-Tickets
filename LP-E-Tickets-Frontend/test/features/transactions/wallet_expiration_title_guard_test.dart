import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/l10n/app_localizations_ar.dart';
import 'package:fueltoken_app/l10n/app_localizations_fr.dart';

void main() {
  test('wallet uses carnet expiration while history keeps QR expiration', () {
    final french = AppLocalizationsFr();
    final arabic = AppLocalizationsAr();
    final source = File(
      'lib/features/transactions/screens/transactions_screen.dart',
    ).readAsStringSync();

    expect(french.txQrExpiration, 'Expiration QR');
    expect(french.walletCarnetExpiration, 'Expiration de carnet');
    expect(arabic.walletCarnetExpiration, 'انتهاء صلاحية الدفتر');
    expect(source, contains('mode == TransactionsScreenMode.wallet'));
    expect(source, contains('l10n.walletCarnetExpiration'));
    expect(source, contains('l10n.txQrExpiration'));
  });
}
