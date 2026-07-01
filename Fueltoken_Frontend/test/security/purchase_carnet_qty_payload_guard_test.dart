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
        contains("final cq = line.qty;"),
        reason: 'line.qty is already a carnet quantity in the purchase UI.',
      );

      expect(
        source,
        contains("'carnet_qty': cq"),
        reason: 'The backend purchase API expects carnet_qty per carnet type.',
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
