import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JSON-RPC requests send the selected application language', () {
    final source = File(
      'lib/data/services/odoo_jsonrpc_client.dart',
    ).readAsStringSync();

    expect(source, contains('await AppPreferences.localeCode()'));
    expect(source, contains("'Accept-Language': languageCode"));
  });

  test('localized RPC cache keys remain outside application preferences', () {
    final preferencesSource = File(
      'lib/core/settings/app_preferences.dart',
    ).readAsStringSync();
    final apiSource = File(
      'lib/data/api/acpec_fueltoken_jsonrpc_api.dart',
    ).readAsStringSync();

    expect(preferencesSource, isNot(contains('RpcCoordinator')));
    expect(apiSource, contains("cacheVariant: 'locale=\$languageCode'"));
  });
}
