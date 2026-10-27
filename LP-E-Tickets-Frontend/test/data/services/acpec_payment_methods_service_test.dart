import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/purchase_services/acpec_payment_methods_service.dart';
import 'package:fueltoken_app/data/services/shared_services/odoo_fueltoken_facade.dart';
import 'package:fueltoken_app/data/services/shared_services/odoo_jsonrpc_client.dart';

class FakePaymentMethodsApi extends OdooFueltokenFacade {
  FakePaymentMethodsApi({this.response, this.failure});

  final dynamic response;
  final Exception? failure;

  @override
  Future<dynamic> paymentMethods([Map<String, dynamic>? params]) async {
    if (failure != null) throw failure!;
    return response;
  }
}

void main() {
  test('an empty catalog is a successful empty result', () async {
    final api = FakePaymentMethodsApi(response: {'items': []});
    expect(await AcpecPaymentMethodsService.listActive(api: api), isEmpty);
  });

  test(
    'valid payment methods preserve backend order and destination',
    () async {
      final api = FakePaymentMethodsApi(
        response: {
          'data': {
            'items': [
              {
                'id': 2,
                'code': 'sedad',
                'name': 'Sedad',
                'merchant_code': '1234',
              },
              {
                'id': 1,
                'code': 'bankily',
                'name': 'Bankily',
                'merchant_code': '56789',
              },
            ],
          },
        },
      );
      final methods = await AcpecPaymentMethodsService.listActive(api: api);
      expect(methods.map((method) => method.code), ['sedad', 'bankily']);
      expect(methods.first.merchantCode, '1234');
    },
  );

  test('network failure is not presented as an empty catalog', () async {
    final api = FakePaymentMethodsApi(
      failure: const SocketException('offline'),
    );
    await expectLater(
      AcpecPaymentMethodsService.listActive(api: api),
      throwsA(isA<SocketException>()),
    );
  });

  test('business failure is propagated to the controller', () async {
    final api = FakePaymentMethodsApi(
      response: {
        'ok': false,
        'error': {'code': 'UNKNOWN_ERROR'},
      },
    );
    await expectLater(
      AcpecPaymentMethodsService.listActive(api: api),
      throwsA(isA<OdooJsonRpcException>()),
    );
  });

  for (final response in [
    <String, dynamic>{},
    {'items': 'invalid'},
    {
      'items': [null],
    },
    {
      'items': [
        {'code': 'bankily'},
      ],
    },
  ]) {
    test(
      'malformed catalog is reported instead of silently filtered: $response',
      () async {
        final api = FakePaymentMethodsApi(response: response);
        await expectLater(
          AcpecPaymentMethodsService.listActive(api: api),
          throwsFormatException,
        );
      },
    );
  }
}
