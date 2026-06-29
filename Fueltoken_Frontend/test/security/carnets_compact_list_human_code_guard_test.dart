import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('carnets compact list human code guard', () {
    test(
      'carnet compact row displays carnet_short_code before carnet_no fallback',
      () {
        final source = File(
          'lib/features/home/screens/faces_detail_screen.dart',
        ).readAsStringSync();

        final shortCodeIndex = source.indexOf('line.carnetShortCode.trim()');
        final carnetNoIndex = source.indexOf('line.carnetNo.trim()');

        expect(source, contains('class _CarnetLineCard'));
        expect(shortCodeIndex, greaterThanOrEqualTo(0));
        expect(carnetNoIndex, greaterThanOrEqualTo(0));
        expect(shortCodeIndex, lessThan(carnetNoIndex));
        expect(source, contains("return 'Code carnet indisponible'"));
        expect(source, contains("'Carnet \$_humanCarnetCode'"));
        expect(source, contains('carnetTypeLabel'));
      },
    );

    test('available quantity wording is explicit tickets ratio wording', () {
      final source = File(
        'lib/features/home/screens/faces_detail_screen.dart',
      ).readAsStringSync();

      expect(source, contains('String _ticketAvailabilityLabel'));
      expect(source, contains('Tickets disponibles'));
      expect(
        source,
        contains(
          r"'Tickets disponibles : ${_ticketAvailabilityLabel(line.availableQty, carnetSize)}'",
        ),
      );
      expect(source, contains('required this.carnetSize'));
      expect(source, contains('carnetSize: _carnetSizeFor(line)'));
      expect(
        source,
        isNot(
          contains(
            r"'${Formatters.numberFr(line.availableQty)} tickets restants'",
          ),
        ),
      );
    });

    test('carnet detail keeps same carnet code and type context', () {
      final source = File(
        'lib/features/home/screens/faces_detail_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_carnetDisplayCodeFor'));
      expect(source, contains("final carnetTitle = 'Carnet \$carnetCode';"));
      expect(
        source,
        contains('final carnetTypeLabel = _carnetTypeLabelFor(line);'),
      );
      expect(source, contains('ticketsAvailableLabel'));
      expect(source, contains('carnetTypeLabel: carnetTypeLabel'));
      expect(source, contains('title: carnetTitle'));
    });

    test('carnet detail displays full carnet_no reference', () {
      final source = File(
        'lib/features/home/screens/faces_detail_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_carnetFullNoFor'));
      expect(source, contains('final fullCarnetNo = _carnetFullNoFor(line);'));
      expect(source, contains('fullCarnetNo: fullCarnetNo'));
      expect(source, contains("'N° complet : \$fullCarnetNo'"));
      expect(source, contains('final String fullCarnetNo;'));
    });

    test('carnet detail displays available amount over total amount', () {
      final source = File(
        'lib/features/home/screens/faces_detail_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains(
          'final availableAmountLabel = _amountLabel(line.availableValue, line);',
        ),
      );
      expect(
        source,
        contains('final totalAmountLabel = _amountLabel(totalAmount, line);'),
      );
      expect(source, contains('availableAmountLabel: availableAmountLabel'));
      expect(source, contains('totalAmountLabel: totalAmountLabel'));
      expect(source, contains(r'Montant disponible : $amountLabel'));
    });

    test('carnet list remains compact and tap opens detail', () {
      final source = File(
        'lib/features/home/screens/faces_detail_screen.dart',
      ).readAsStringSync();

      expect(source, contains('onTap: onTap'));
      expect(source, contains('Row('));
      expect(source, contains('Icons.confirmation_number_outlined'));
      expect(source, contains('Expire le'));
    });
  });
}
