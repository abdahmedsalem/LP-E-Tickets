import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('purchase proof picker is aligned with backend Patch43K1B guard', () {
    final source = File(
      'lib/features/purchases/screens/submit_purchase_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('PurchasePaymentProofGuard.allowedExtensions'),
      reason: 'The picker must not keep a divergent frontend extension list.',
    );
    expect(
      source,
      isNot(contains("'webp'")),
      reason: 'Backend Patch43K1B rejects WEBP; Flutter must not offer it.',
    );
    expect(
      source,
      contains('validateFileNameAndSize'),
      reason: 'Extension and size must be checked before reading bytes.',
    );
    expect(
      source,
      contains('validateBytes'),
      reason:
          'The selected proof content signature must be checked before submit.',
    );
    expect(
      source,
      contains("'proof_filename': fileName"),
      reason:
          'The backend requires a reliable filename/extension for proof validation.',
    );
    expect(
      source,
      contains("'proof_data': base64Encode(proofBytes)"),
      reason: 'Only bytes that passed the frontend guard should be encoded.',
    );
  });
}
