import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';

void main() {
  test('QR list translations are available in Arabic', () {
    final arabic = lookupAppLocalizations(const Locale('ar'));

    expect(arabic.qrsTitle, 'رموز QR الخاصة بي');
    expect(arabic.qrFilterActive, 'النشطة');
    expect(arabic.qrFilterBlocked, 'المحظورة');
    expect(arabic.qrStatusConsumed, 'مستهلك');
    expect(arabic.qrsEmptyTitle, 'لا توجد رموز QR');
    expect(arabic.commonRefresh, 'تحديث');
    expect(arabic.qrExpiresFrom('16-07-2026'), contains('16-07-2026'));
    expect(arabic.qrConsumedOn('16-07-2026'), contains('16-07-2026'));
  });

  test('QR list reads visible labels from AppLocalizations', () {
    final source = File(
      'lib/features/qr/screens/qr_list_screen.dart',
    ).readAsStringSync();

    expect(source, contains('AppLocalizations.of(context)'));
    expect(source, contains('l10n.qrsTitle'));
    expect(source, contains('l10n.qrStatusActive'));
    expect(source, contains('l10n.qrsEmptyMessage'));
    expect(source, isNot(contains("title: 'Mes QR'")));
    expect(source, isNot(contains("'Expiration non définie'")));
  });
}
