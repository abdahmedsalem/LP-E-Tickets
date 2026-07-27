import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/services/acpec_wallet_mapper.dart';
import 'package:fueltoken_app/data/services/odoo_jsonrpc_client.dart';

void main() {
  group('AcpecWalletMapper', () {
    test('remonte une session expiree comme erreur auth', () {
      expect(
        () => AcpecWalletMapper.fromRpcResult(<String, dynamic>{
          'ok': false,
          'code': 401,
          'message': 'Session expired',
        }, ownerId: 'u1'),
        throwsA(
          isA<OdooJsonRpcException>().having(
            (e) => e.isOdooSessionExpired,
            'isOdooSessionExpired',
            true,
          ),
        ),
      );
    });
  });
}
