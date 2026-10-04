import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/station_services/acpec_station_profile_mapper.dart';
import 'package:fueltoken_app/domain/models/station/station_profile.dart';

void main() {
  test('maps nested station and operator RPC records to domain profile', () {
    final profile = AcpecStationProfileMapper.fromRpc({
      'ok': true,
      'data': {
        'station': {
          'id': 42,
          'name': 'Station Tevragh Zeina',
          'code': 'TZ-42',
          'address': 'Nouakchott',
          'active': false,
        },
        'operator': {
          'id': 7,
          'name': 'Agent',
          'email': 'agent@example.mr',
          'phone': '22223333',
        },
      },
    });

    expect(profile, isA<StationProfile>());
    expect(profile.stationId, '42');
    expect(profile.stationName, 'Station Tevragh Zeina');
    expect(profile.stationCode, 'TZ-42');
    expect(profile.stationAddress, 'Nouakchott');
    expect(profile.stationActive, isFalse);
    expect(profile.operatorId, '7');
    expect(profile.operatorName, 'Agent');
    expect(profile.operatorEmail, 'agent@example.mr');
    expect(profile.operatorPhone, '22223333');
  });

  test('session profile keeps fallback labels without API parsing', () {
    final profile = StationProfile.fromSessionDetails(
      stationName: 'My Company',
      stationId: null,
      operatorName: '',
      operatorEmail: ' agent@example.mr ',
      operatorPhone: ' 22223333 ',
      operatorId: '',
    );

    expect(profile.stationName, 'Station');
    expect(profile.stationId, '—');
    expect(profile.operatorName, 'Opérateur station');
    expect(profile.operatorId, '—');
    expect(profile.operatorEmail, 'agent@example.mr');
    expect(profile.operatorPhone, '22223333');
  });
}
