import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('purchase success keeps the localized carnet type name from API', () {
    final source = File(
      'lib/shared/widgets/purchase_submit_success_dialog.dart',
    ).readAsStringSync();
    final start = source.indexOf('class _PurchasedLineRow');
    final end = source.indexOf('\nclass ', start + 1);
    final purchasedRow = source.substring(
      start,
      end == -1 ? source.length : end,
    );

    expect(purchasedRow, contains('Formatters.carnetTypeLabelFromServer('));
    expect(purchasedRow, contains('line.carnetType.name'));
    expect(purchasedRow, isNot(contains('Formatters.carnetTypeLabel(')));
  });
}
