import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Odoo JSON-RPC client delegates HTTP failures to Dio mapping', () {
    final source = File(
      'lib/data/services/odoo_jsonrpc_client.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('validateStatus: (s) => s != null && s >= 200 && s < 300,'),
    );
    expect(
      source,
      isNot(contains('validateStatus: (s) => s != null && s < 600')),
    );
    expect(
      source,
      contains('final httpFailure = odooJsonRpcHttpFailure(r.statusCode);'),
    );
    expect(source, contains('throw odooJsonRpcExceptionFromDio(e);'));
    expect(source, isNot(contains('class AcpecHttpException')));
    expect(source, isNot(contains('class AcpecApiResponseDecoder')));
  });
}
