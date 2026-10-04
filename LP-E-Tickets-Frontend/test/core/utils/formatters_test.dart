import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fueltoken_app/core/utils/formatters.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('ar');
  });

  setUp(() => Formatters.setLocaleCode('fr'));

  group('Formatters dates', () {
    final value = DateTime(2026, 7, 15, 9, 8, 7);

    test('uses dashes for a date without time', () {
      expect(Formatters.date(value), '15-07-2026');
    });

    test('uses seconds for every date and time display', () {
      expect(Formatters.dateTime(value), '15-07-2026 09:08:07');
      expect(Formatters.dateTimeDash(value), '15-07-2026 09:08:07');
    });
  });

  test('number formatting follows the selected app locale', () {
    Formatters.setLocaleCode('ar');
    expect(
      Formatters.number(123456),
      NumberFormat.decimalPattern('ar').format(123456),
    );

    Formatters.setLocaleCode('fr');
    expect(
      Formatters.number(123456),
      NumberFormat.decimalPattern('fr_FR').format(123456),
    );
  });

  test('date formatting follows the selected app locale', () {
    final value = DateTime(2026, 7, 15, 9, 8, 7);
    Formatters.setLocaleCode('ar');
    expect(
      Formatters.date(value),
      DateFormat('dd-MM-yyyy', 'ar').format(value),
    );

    Formatters.setLocaleCode('fr');
    expect(
      Formatters.date(value),
      DateFormat('dd-MM-yyyy', 'fr_FR').format(value),
    );
  });

  group('Formatters.carnetTypeLabelFromServer', () {
    test('uses the real technical code when the server name is missing', () {
      expect(
        Formatters.carnetTypeLabelFromServer('', fallbackCode: 'C10T-500'),
        'C10T-500',
      );
    });

    test('keeps the localized server name unchanged', () {
      const arabicName = 'دفتر - 10 تذاكر × 500 أوقية';
      expect(
        Formatters.carnetTypeLabelFromServer(
          arabicName,
          fallbackCode: 'C10T-500',
        ),
        arabicName,
      );
    });

    test('does not compose a name when server name and code are missing', () {
      expect(Formatters.carnetTypeLabelFromServer(''), isEmpty);
    });
  });
}
