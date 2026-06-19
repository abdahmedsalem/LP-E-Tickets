import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/core/utils/formatters.dart';

void main() {
  group('Formatters.normalizeCarnetTypeLabel', () {
    test('normalizes star separator to multiplication sign', () {
      expect(
        Formatters.normalizeCarnetTypeLabel('Carnet 10 * 1000'),
        Formatters.carnetTypeLabel(10, 1000),
      );
    });

    test('normalizes x separator to multiplication sign', () {
      expect(
        Formatters.normalizeCarnetTypeLabel('Carnet 10 x 1000'),
        Formatters.carnetTypeLabel(10, 1000),
      );
    });
  });
}
