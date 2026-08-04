import 'package:flutter_test/flutter_test.dart';

import 'package:fueltoken_app/data/services/acpec_carnet_types_mapper.dart';

void main() {
  group('AcpecCarnetTypesMapper', () {
    test('falls back to the backend code when backend name is missing', () {
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
      expect(rows!.first.name, 'C10T-1000');
      expect(rows.first.code, 'C10T-1000');
    });

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

    test('keeps localized Arabic carnet type name unchanged', () {
      const arabicName = 'دفتر - 10 تذاكر × 100 أوقية';
      final rows = AcpecCarnetTypesMapper.tryListFromRpc({
        'data': [
          {
            'carnet_type_id': 7,
            'code': 'C10T-100',
            'face_value': 100,
            'carnet_size': 10,
            'currency_name': 'MRU',
            'carnet_type_name': arabicName,
          },
        ],
      }, companyId: '1');

      expect(rows, isNotNull);
      expect(rows, hasLength(1));
      expect(rows!.first.name, arabicName);
    });

    test('uses name_ar when the active language is Arabic', () {
      const arabicName =
          '\u062f\u0641\u062a\u0631 - 10 \u062a\u0630\u0627\u0643\u0631';
      final rows = AcpecCarnetTypesMapper.tryListFromRpc(
        {
          'data': [
            {
              'carnet_type_id': 7,
              'code': 'C10T-100',
              'face_value': 100,
              'carnet_size': 10,
              'name': 'Carnet - 10 tickets x 100 MRU',
              'carnet_type_name': 'Carnet - 10 tickets x 100 MRU',
              'name_ar': arabicName,
            },
          ],
        },
        companyId: '1',
        languageCode: 'ar',
      );

      expect(rows, isNotNull);
      expect(rows!.first.name, arabicName);
    });

    test('falls back to the default name when name_ar is empty', () {
      final rows = AcpecCarnetTypesMapper.tryListFromRpc(
        {
          'data': [
            {
              'carnet_type_id': 7,
              'code': 'C10T-100',
              'face_value': 100,
              'carnet_size': 10,
              'name': 'Carnet - 10 tickets x 100 MRU',
              'name_ar': '   ',
            },
          ],
        },
        companyId: '1',
        languageCode: 'ar-MR',
      );

      expect(rows, isNotNull);
      expect(rows!.first.name, 'Carnet - 10 tickets x 100 MRU');
    });

    test('keeps the default name when the active language is French', () {
      final rows = AcpecCarnetTypesMapper.tryListFromRpc(
        {
          'data': [
            {
              'carnet_type_id': 7,
              'code': 'C10T-100',
              'face_value': 100,
              'carnet_size': 10,
              'name': 'Carnet - 10 tickets x 100 MRU',
              'name_ar': '\u062f\u0641\u062a\u0631',
            },
          ],
        },
        companyId: '1',
        languageCode: 'fr',
      );

      expect(rows, isNotNull);
      expect(rows!.first.name, 'Carnet - 10 tickets x 100 MRU');
    });

    test('keeps a legacy backend name unchanged', () {
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
      expect(rows!.first.name, 'Carnet de 10 tickets - 300USD');
      expect(rows.first.code, 'C10T-300');
    });
  });
}
