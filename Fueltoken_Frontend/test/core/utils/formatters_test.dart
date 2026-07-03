import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/core/utils/formatters.dart';

void main() {
  group('Formatters.carnetTypeLabel', () {
    test('uses backend K4 human format with default currency', () {
      expect(
        Formatters.carnetTypeLabel(10, 1000),
        'Carnet - 10 tickets x 1000 MRU',
      );
    });

    test('uses ticket singular', () {
      expect(
        Formatters.carnetTypeLabel(1, 250, currency: 'USD'),
        'Carnet - 1 ticket x 250 USD',
      );
    });
  });

  group('Formatters.normalizeCarnetTypeLabel', () {
    test('keeps backend canonical K4 label unchanged', () {
      expect(
        Formatters.normalizeCarnetTypeLabel('Carnet - 10 tickets x 100 USD'),
        'Carnet - 10 tickets x 100 USD',
      );
    });

    test('normalizes star separator to K4 human format', () {
      expect(
        Formatters.normalizeCarnetTypeLabel('Carnet 10 * 1000'),
        'Carnet - 10 tickets x 1000 MRU',
      );
    });

    test('normalizes x separator to K4 human format', () {
      expect(
        Formatters.normalizeCarnetTypeLabel('Carnet 10 x 1000'),
        'Carnet - 10 tickets x 1000 MRU',
      );
    });

    test('normalizes legacy long label with glued currency', () {
      expect(
        Formatters.normalizeCarnetTypeLabel('Carnet de 10 tickets - 300USD'),
        'Carnet - 10 tickets x 300 USD',
      );
    });
  });

  group('Formatters.carnetTypeLabelFromServer', () {
    test('uses fallback human label before technical code', () {
      expect(
        Formatters.carnetTypeLabelFromServer(
          '',
          fallbackSize: 10,
          fallbackFaceValue: 500,
          fallbackCode: 'C10T-500',
          fallbackCurrency: 'USD',
        ),
        'Carnet - 10 tickets x 500 USD',
      );
    });

    test('keeps technical code only when no human fallback is available', () {
      expect(
        Formatters.carnetTypeLabelFromServer('', fallbackCode: 'C10T-500'),
        'C10T-500',
      );
    });
  });
}
