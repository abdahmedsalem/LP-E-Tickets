import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/core/utils/formatters.dart';

void main() {
  group('Formatters.carnetTypeLabelFromServer', () {
    test('keeps the localized backend name unchanged', () {
      expect(
        Formatters.carnetTypeLabelFromServer(
          'دفتر - 10 تذاكر × 100 أوقية',
          fallbackCode: 'C10T-100',
        ),
        'دفتر - 10 تذاكر × 100 أوقية',
      );
    });

    test('uses the backend code when the localized name is missing', () {
      expect(
        Formatters.carnetTypeLabelFromServer('', fallbackCode: 'C10T-100'),
        'C10T-100',
      );
    });
  });
}
