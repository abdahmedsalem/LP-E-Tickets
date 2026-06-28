import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/models/app_user.dart';
import 'package:fueltoken_app/data/models/user_role.dart';

void main() {
  AppUser userWithTrust(String? state) {
    return AppUser(
      id: 'u1',
      email: '',
      name: 'Test',
      phone: '22222222',
      role: UserRole.user,
      deviceTrustState: state,
      createdAt: DateTime(2026),
    );
  }

  test('routes trusted, pending and blocked device states distinctly', () {
    expect(userWithTrust('trusted').isDeviceTrusted, isTrue);
    expect(userWithTrust('trusted').isDeviceActivationPending, isFalse);
    expect(userWithTrust('trusted').isDeviceBlocked, isFalse);

    expect(userWithTrust('pending_trust').isDeviceTrusted, isFalse);
    expect(userWithTrust('pending_trust').isDeviceActivationPending, isTrue);
    expect(userWithTrust('pending_trust').isDeviceBlocked, isFalse);

    expect(userWithTrust('blocked').isDeviceTrusted, isFalse);
    expect(userWithTrust('blocked').isDeviceActivationPending, isFalse);
    expect(userWithTrust('blocked').isDeviceBlocked, isTrue);
  });
}
