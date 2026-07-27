import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('purchase offer cards leave room for Arabic font metrics', () {
    final source = File(
      'lib/features/purchases/screens/submit_purchase_screen.dart',
    ).readAsStringSync();

    expect(source, contains('const double _kPurchaseOfferCardHeight = 112;'));
    expect(
      RegExp(r'_kPurchaseOfferCardHeight').allMatches(source).length,
      3,
      reason: 'the grid and loading skeleton must share the safe card height',
    );
    expect(source, isNot(contains('mainAxisExtent: 110')));
  });
}
