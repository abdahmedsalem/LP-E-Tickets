import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/auth_services/app_user_mapper.dart';
import 'package:fueltoken_app/domain/models/user_role.dart';

void main() {
  test('maps nested Odoo profile and device trust fields into domain user', () {
    final user = AppUserMapper.fromOdooProfileMap({
      'user': {
        'id': 17,
        'email': 'station@example.mr',
        'name': 'Station Test',
        'phone': '22223333',
        'role': 'station',
        'company_id': 'acpec',
        'station_id': 42,
        'station_name': 'Station 42',
        'device_trust_state': 'pending_approval',
        'device_trust_required_for_sensitive': true,
      },
    });

    expect(user.id, '17');
    expect(user.role, UserRole.station);
    expect(user.companyId, 'acpec');
    expect(user.stationId, '42');
    expect(user.stationName, 'Station 42');
    expect(user.isDeviceActivationPending, isTrue);
    expect(user.deviceTrustRequiredForSensitive, isTrue);
  });

  test('keeps the highest role resolved from the Odoo envelope', () {
    final user = AppUserMapper.fromOdooProfileMap(
      {'id': 8, 'email': 'admin@example.mr', 'name': 'Admin', 'role': 'user'},
      envelope: {
        'data': {'is_superuser': true},
      },
    );

    expect(user.role, UserRole.admin);
  });
}
