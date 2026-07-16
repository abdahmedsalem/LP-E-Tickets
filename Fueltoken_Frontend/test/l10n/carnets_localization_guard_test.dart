import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';

void main() {
  test('carnet list and detail translations are available in Arabic', () {
    final arabic = lookupAppLocalizations(const Locale('ar'));

    expect(arabic.carnetsTitle, 'دفاتري');
    expect(arabic.carnetsSummaryTitle, 'ملخص المحفظة');
    expect(arabic.carnetsAvailableTickets, 'التذاكر المتاحة');
    expect(arabic.filterAvailable, 'المتاحة');
    expect(arabic.carnetsEmptyTitle, 'لا توجد دفاتر');
    expect(arabic.carnetDetailTitle, 'تفاصيل الدفتر');
    expect(arabic.referenceCode, 'الرمز المرجعي');
    expect(arabic.carnetWithCode('ABC'), 'دفتر ABC');
    expect(arabic.carnetExpiresOn('16-07-2026'), contains('16-07-2026'));
  });

  test('carnet screen reads visible labels from AppLocalizations', () {
    final source = File(
      'lib/features/home/screens/faces_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains('AppLocalizations.of(context)'));
    expect(source, contains('l10n.carnetsTitle'));
    expect(source, contains('l10n.carnetDetailTitle'));
    expect(source, isNot(contains("title: 'Mes carnets'")));
    expect(source, isNot(contains("label: 'Code de référence'")));
    expect(source, isNot(contains("'Expire le \${")));
  });
}
