import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _facesDetailScreenSource() {
  final candidates = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  for (final file in candidates) {
    final source = file.readAsStringSync();
    if (source.contains('class FacesDetailScreen') &&
        source.contains('_carnetDisplayCodeFor')) {
      return source;
    }
  }

  fail('FacesDetailScreen source not found.');
}

void main() {
  group('carnets compact list human code guard', () {
    test(
      'carnet reference uses carnet_short_code before carnet_no fallback',
      () {
        final source = _facesDetailScreenSource();

        expect(source, contains('String _carnetDisplayCodeFor(FaceLine line)'));
        expect(source, contains('line.carnetShortCode.trim()'));
        expect(source, contains('line.carnetNo.trim()'));
        expect(source, contains('.carnetCodeUnavailable'));
        expect(source, contains('l10n.carnetWithCode(carnetCode)'));

        final shortCodeIndex = source.indexOf('line.carnetShortCode.trim()');
        final carnetNoIndex = source.indexOf('line.carnetNo.trim()');

        expect(shortCodeIndex, greaterThanOrEqualTo(0));
        expect(carnetNoIndex, greaterThanOrEqualTo(0));
        expect(shortCodeIndex, lessThan(carnetNoIndex));
      },
    );

    test('carnet type label uses backend label and K4 fallback format', () {
      final source = _facesDetailScreenSource();

      expect(source, contains('String _carnetTypeLabelFor(FaceLine line)'));
      expect(source, contains('final rawName = line.carnetTypeName.trim();'));
      expect(source, contains('return _normalizedCarnetLabel(rawName);'));
      expect(source, contains('carnetTypeFallback('));
      expect(source, contains('_currencyFor(line),'));
      expect(source, isNot(contains('Carnet de 10 tickets')));
      expect(source, isNot(contains('10 tickets x 100 MRU')));
    });

    test('carnet detail keeps explicit non-sensitive labels', () {
      final source = _facesDetailScreenSource();

      expect(source, contains('l10n.referenceCode'));
      expect(source, contains('l10n.carnetFullNumber'));
      expect(source, contains('l10n.carnetsAvailableTickets'));
      expect(source, contains('l10n.availableAmount'));
      expect(source, contains('ticketsAvailableLabel'));
      expect(source, contains('availableAmountLabel'));
      expect(source, contains('fullCarnetNo'));
    });

    test('carnet screens do not display QR manual secret fields', () {
      final source = _facesDetailScreenSource();

      expect(source, isNot(contains('qr_numeric_code')));
      expect(source, isNot(contains('qrNumericCode')));
      expect(source, isNot(contains('manualQrCode')));
      expect(source, isNot(contains('qrManualCode')));
      expect(source, isNot(contains('public_code')));
    });

    test('carnet list remains compact and tap expands detail', () {
      final source = _facesDetailScreenSource();

      expect(
        source,
        contains('onTap: () => setState(() => _expanded = !_expanded)'),
      );
      expect(source, contains('Row('));
      expect(source, contains('Icons.confirmation_number_outlined'));
      expect(source, contains('l10n.carnetExpiresOn('));
    });
  });
}
