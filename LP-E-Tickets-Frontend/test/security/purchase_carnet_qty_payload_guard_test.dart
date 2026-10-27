import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'purchase submit sends selected carnet quantity directly as carnet_qty',
    () {
      final source = File(
        'lib/features/purchases/screens/submit_purchase_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains("'carnet_qty': line.qty"),
        reason:
            'The selected carnet quantity is sent without ticket conversion.',
      );

      expect(
        source,
        isNot(contains('acpecOdooCarnetQtyFromTicketSelection(')),
        reason:
            'The purchase UI selects carnets, not tickets. Converting line.qty '
            'as tickets regresses 3/2/1 carnets into 1/1/1.',
      );
    },
  );
}
