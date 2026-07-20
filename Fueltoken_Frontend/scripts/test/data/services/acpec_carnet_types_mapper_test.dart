import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/services/acpec_carnet_types_mapper.dart';

void main() {
  group('AcpecCarnetTypesMapper', () {
    test('falls back to the backend code when backend name is missing', () {
      final rows = AcpecCarnetTypesMapper.tryListFromRpc({
        'data': [
          {
            'carnet_type_id': 7,
            'code': 'C10-1000',
            'face_value': 1000,
            'carnet_size': 10,
          },
        ],
      }, companyId: '1');

      expect(rows, isNotNull);
      expect(rows, hasLength(1));
      expect(rows!.first.name, 'C10-1000');
    });

    test('keeps backend carnet type name when present', () {
      final rows = AcpecCarnetTypesMapper.tryListFromRpc({
        'data': [
          {
            'carnet_type_id': 7,
            'code': 'C10-1000',
            'face_value': 1000,
            'carnet_size': 10,
            'carnet_type_name': 'Carnet 10 * 1000',
          },
        ],
      }, companyId: '1');

      expect(rows, isNotNull);
      expect(rows, hasLength(1));
      expect(rows!.first.name, 'Carnet 10 * 1000');
    });
  });
}
