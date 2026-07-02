import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/services/acpec_public_api_error.dart';
import 'package:fueltoken_app/data/services/acpec_rpc_result_guard.dart';
import 'package:fueltoken_app/data/services/odoo_jsonrpc_client.dart';

void main() {
  group('AcpecPublicApiError', () {
    test('maps result.error.code and appends a SEC reference', () {
      final error = AcpecPublicApiError.fromBusinessEnvelope({
        'ok': false,
        'success': false,
        'error': {
          'code': 'RATE_LIMITED',
          'message': 'backend message must not drive Flutter UX',
          'reference': 'SEC-20260628-ABC',
          'debug_reason': 'hidden',
        },
      });

      expect(error.code, 'RATE_LIMITED');
      expect(error.normalizedReference, 'SEC-20260628-ABC');
      expect(error.displayMessage, contains('Trop de tentatives'));
      expect(error.displayMessage, contains('SEC-20260628-ABC'));
      expect(error.displayMessage, isNot(contains('backend message')));
      expect(error.displayMessage, isNot(contains('debug_reason')));
    });

    test('uses a safe fallback for an unknown public code', () {
      final error = AcpecPublicApiError.fromBusinessEnvelope({
        'ok': false,
        'error': {'code': 'NEW_BACKEND_CODE', 'reference': 'ERR-XYZ'},
      });

      expect(error.code, 'NEW_BACKEND_CODE');
      expect(error.displayMessage, contains('Demande refusée'));
      expect(error.displayMessage, contains('ERR-XYZ'));
    });

    test('maps backend payment proof invalid code locally', () {
      final error = AcpecPublicApiError.fromBusinessEnvelope({
        'ok': false,
        'success': false,
        'error': {
          'code': 'PAYMENT_PROOF_INVALID',
          'message': 'raw backend message must not drive Flutter UX',
        },
      });

      expect(error.code, 'PAYMENT_PROOF_INVALID');
      expect(error.displayMessage, contains('Preuve de paiement invalide'));
      expect(error.displayMessage, contains('JPG'));
      expect(error.displayMessage, contains('PNG'));
      expect(error.displayMessage, contains('PDF'));
      expect(error.displayMessage, isNot(contains('raw backend message')));
    });
  });

  group('acpecRpcMapOrThrow', () {
    test(
      'throws on business error using code mapping, not backend message',
      () {
        expect(
          () => acpecRpcMapOrThrow({
            'ok': false,
            'success': false,
            'error': {
              'code': 'DEVICE_NOT_ALLOWED',
              'message': 'raw backend wording',
              'reference': 'SEC-DEVICE-1',
            },
          }, fallbackMessage: 'fallback'),
          throwsA(
            isA<OdooJsonRpcException>()
                .having((e) => e.publicCode, 'publicCode', 'DEVICE_NOT_ALLOWED')
                .having((e) => e.reference, 'reference', 'SEC-DEVICE-1')
                .having((e) => e.message, 'message', isNot(contains('raw'))),
          ),
        );
      },
    );
  });
}
