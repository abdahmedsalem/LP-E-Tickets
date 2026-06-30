import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('admin purchase approval action code guard', () {
    test('purchase approval prompts for action_code and idempotency_key', () {
      final source = File(
        'lib/features/purchases/screens/purchase_detail_screen.dart',
      ).readAsStringSync();

      expect(source, contains('showSensitiveActionCodeDialog'));
      expect(source, contains("title: 'Confirmer la validation'"));
      expect(
        source,
        contains("SensitiveActionIntent.create('purchase-approve')"),
      );
      expect(source, contains('intent.withAuthParams'));
      expect(source, contains('actionCode: actionCode'));
      expect(source, contains("'purchase_id': purchaseId"));
      expect(
        source,
        isNot(
          contains(
            "adminPurchasesApprove({\n          'purchase_id': purchaseId,\n        })",
          ),
        ),
      );
    });
  });
}
