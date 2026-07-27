import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fueltoken_app/core/settings/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a fresh installation still requires an explicit language choice',
    () async {
      SharedPreferences.setMockInitialValues({});

      expect(await AppPreferences.localeCode(), 'fr');
      expect(await AppPreferences.hasSelectedLanguage(), isFalse);
    },
  );

  test(
    'selecting Arabic stores both locale and first-install completion',
    () async {
      SharedPreferences.setMockInitialValues({});

      await AppPreferences.setLocaleCode('ar');

      expect(await AppPreferences.localeCode(), 'ar');
      expect(await AppPreferences.hasSelectedLanguage(), isTrue);
    },
  );

  test(
    'existing installations with a locale skip language selection',
    () async {
      SharedPreferences.setMockInitialValues({'ft_app_locale': 'fr'});

      expect(await AppPreferences.hasSelectedLanguage(), isTrue);
    },
  );
}
