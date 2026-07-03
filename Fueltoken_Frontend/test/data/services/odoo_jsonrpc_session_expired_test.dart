import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/odoo_jsonrpc_client.dart';

void main() {
  group('OdooJsonRpc session expired business code', () {
    test('SESSION_EXPIRED business envelope is an auth failure', () {
      final exception = odooJsonRpcAuthFailureFromBusinessResult({
        'ok': false,
        'success': false,
        'error': {
          'code': 'SESSION_EXPIRED',
          'message': 'Session mobile invalide ou expirée.',
        },
      });

      expect(exception, isNotNull);
      expect(exception!.code, 401);
      expect(exception.publicCode, 'SESSION_EXPIRED');
      expect(exception.requiresReLogin, isTrue);
    });

    test('generic ACCESS_ERROR is not treated as session refresh signal', () {
      final exception = odooJsonRpcAuthFailureFromBusinessResult({
        'ok': false,
        'success': false,
        'error': {
          'code': 'ACCESS_ERROR',
          'message': 'Droits insuffisants pour cette opération.',
        },
      });

      expect(exception, isNull);
    });

    test('SESSION_EXPIRED is detected when nested under data envelope', () {
      final exception = odooJsonRpcAuthFailureFromBusinessResult({
        'data': {
          'ok': false,
          'error': {
            'code': 'SESSION_EXPIRED',
          },
        },
      });

      expect(exception, isNotNull);
      expect(exception!.publicCode, 'SESSION_EXPIRED');
      expect(exception.requiresReLogin, isTrue);
    });
  });
}
