import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user interfaces never compose carnet type names locally', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('Formatters.carnetTypeLabel(')),
        reason: file.path,
      );
      expect(
        source,
        isNot(contains('Formatters.normalizeCarnetTypeLabel(')),
        reason: file.path,
      );
      expect(
        source,
        isNot(contains('.carnetTypeFallback(')),
        reason: file.path,
      );
    }
  });

  test('catalog mapper falls back to code instead of composing a name', () {
    final source = File(
      'lib/data/services/acpec_carnet_types_mapper.dart',
    ).readAsStringSync();

    expect(source, contains('if (name.isEmpty) name = code;'));
    expect(source, isNot(contains('Formatters.carnetTypeLabel(')));
  });
}
