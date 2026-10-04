import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stations map screen renders FlutterMap with backend station markers',
    () {
      final source = File(
        'lib/features/station/accueil/stations_map_screen.dart',
      ).readAsStringSync();
      final repository = File(
        'lib/data/repositories/station_repository.dart',
      ).readAsStringSync();
      final facade = File(
        'lib/data/services/shared_services/odoo_fueltoken_facade.dart',
      ).readAsStringSync();
      final routes = File(
        'lib/core/config/odoo_fueltoken_rpc_config.dart',
      ).readAsStringSync();

      expect(source, contains('FlutterMap('));
      expect(source, contains('TileLayer('));
      expect(source, contains('MarkerLayer('));
      expect(repository, contains('_facade.stationList()'));
      expect(facade, contains('OdooFueltokenRpcConfig.stationList'));
      expect(routes, contains('/api/acpec/fueltoken/v1/mobile/stations/list'));
      expect(source, contains('openExternalUrl'));
      expect(source, contains('&travelmode=driving&dir_action=navigate'));
      expect(source, isNot(contains('_selectedCityFilter')));
      expect(source, isNot(contains('_CityFilterChip')));
      expect(source, isNot(contains('Clipboard.setData')));
    },
  );

  test('external URL opener supports Android and iOS applications', () {
    final source = File(
      'lib/core/utils/external_url_opener_io.dart',
    ).readAsStringSync();

    expect(source, contains("package:url_launcher/url_launcher.dart"));
    expect(source, contains('LaunchMode.externalApplication'));
    expect(source, isNot(contains('Platform.isWindows')));
  });
}
