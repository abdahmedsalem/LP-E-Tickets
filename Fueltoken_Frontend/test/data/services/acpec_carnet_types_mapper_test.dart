import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/services/acpec_carnet_types_mapper.dart';

void main() {
  group('AcpecCarnetTypesMapper', () {
    test(
      'falls back to K4 human carnet label when backend name is missing',
      () {
        final rows = AcpecCarnetTypesMapper.tryListFromRpc({
          'data': [
            {
              'carnet_type_id': 7,
              'code': 'C10T-1000',
              'face_value': 1000,
              'carnet_size': 10,
              'currency_name': 'USD',
            },
          ],
        }, companyId: '1');

        expect(rows, isNotNull);
        expect(rows, hasLength(1));
        expect(rows!.first.name, 'Carnet - 10 tickets x 1000 USD');
        expect(rows.first.code, 'C10T-1000');
      },
    );

    test('keeps backend K4 carnet type name when present', () {
      final rows = AcpecCarnetTypesMapper.tryListFromRpc({
        'data': [
          {
            'carnet_type_id': 7,
            'code': 'C10T-1000',
            'face_value': 1000,
            'carnet_size': 10,
            'currency_name': 'USD',
            'carnet_type_name': 'Carnet - 10 tickets x 1000 USD',
          },
        ],
      }, companyId: '1');

      expect(rows, isNotNull);
      expect(rows, hasLength(1));
      expect(rows!.first.name, 'Carnet - 10 tickets x 1000 USD');
      expect(rows.first.code, 'C10T-1000');
    });

    test('normalizes legacy carnet type name to K4 format', () {
      final rows = AcpecCarnetTypesMapper.tryListFromRpc({
        'data': [
          {
            'carnet_type_id': 7,
            'code': 'C10T-300',
            'face_value': 300,
            'carnet_size': 10,
            'currency_name': 'USD',
            'carnet_type_name': 'Carnet de 10 tickets - 300USD',
          },
        ],
      }, companyId: '1');

      expect(rows, isNotNull);
      expect(rows, hasLength(1));
      expect(rows!.first.name, 'Carnet - 10 tickets x 300 USD');
      expect(rows.first.code, 'C10T-300');
    });
  });
}
