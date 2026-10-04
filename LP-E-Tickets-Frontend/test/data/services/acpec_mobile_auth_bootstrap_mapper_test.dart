import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/services/auth_services/acpec_mobile_auth_bootstrap_mapper.dart';
import 'package:fueltoken_app/domain/models/auth/acpec_mobile_auth_bootstrap.dart';

void main() {
  test('maps version response from the ACPEC envelope', () {
    final result = AcpecMobileAuthBootstrapMapper.versionFromResponse({
      'ok': true,
      'data': {
        'status': 'available',
        'min_supported_version': true,
        'latest_version': false,
        'force_update': false,
        'message': 'Mise à jour facultative',
      },
    });

    expect(result.status, 'available');
    expect(result.minSupportedVersion, isTrue);
    expect(result.latestVersion, isFalse);
    expect(result.messageRaw, 'Mise à jour facultative');
  });

  test('maps company ids from integers and numeric strings', () {
    final result = AcpecMobileAuthBootstrapMapper.companiesFromResponse({
      'ok': true,
      'data': {
        'items': [
          {'id': 12, 'name': 'Station A'},
          {'id': '13', 'name': ' '},
          {'id': 'bad', 'name': 'Ignored'},
        ],
      },
    });

    expect(result.map((company) => company.id), [12, 13]);
    expect(result.last.name, '—');
  });

  test('rejects unsuccessful or malformed response envelopes', () {
    expect(
      () => AcpecMobileAuthBootstrapMapper.versionFromResponse({'ok': false}),
      throwsA(isA<AcpecBootstrapFailure>()),
    );
    expect(
      () => AcpecMobileAuthBootstrapMapper.companiesFromResponse({'ok': true}),
      throwsA(isA<AcpecBootstrapFailure>()),
    );
  });
}
