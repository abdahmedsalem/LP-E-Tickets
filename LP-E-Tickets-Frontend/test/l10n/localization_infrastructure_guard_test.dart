import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('French and Arabic catalogs expose the same translation keys', () {
    Map<String, dynamic> readCatalog(String path) {
      return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    }

    Set<String> translationKeys(Map<String, dynamic> catalog) {
      return catalog.keys.where((key) => !key.startsWith('@')).toSet();
    }

    final french = readCatalog('lib/l10n/app_fr.arb');
    final arabic = readCatalog('lib/l10n/app_ar.arb');

    expect(french['@@locale'], 'fr');
    expect(arabic['@@locale'], 'ar');
    expect(translationKeys(arabic), translationKeys(french));
  });
}
