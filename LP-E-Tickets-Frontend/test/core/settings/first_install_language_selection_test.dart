import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fueltoken_app/core/settings/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in <String, List<Locale>>{
    'ar': [const Locale('ar', 'MR')],
    'fr': [const Locale('fr', 'FR')],
    'fallback': [const Locale('en', 'US')],
    'preferred-supported': [const Locale('en'), const Locale('ar')],
  }.entries) {
    test(
      'fresh installation resolves system language: ${scenario.key}',
      () async {
        final dispatcher =
            TestWidgetsFlutterBinding.instance.platformDispatcher;
        dispatcher.localesTestValue = scenario.value;
        addTearDown(dispatcher.clearLocalesTestValue);
        SharedPreferences.setMockInitialValues({});
        final expected =
            scenario.key == 'ar' || scenario.key == 'preferred-supported'
            ? 'ar'
            : 'fr';
        expect(await AppPreferences.localeCode(), expected);
        expect(AppPreferences.localeNotifier.value, expected);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('ft_app_locale'), expected);
        expect(await AppPreferences.hasSelectedLanguage(), isTrue);
      },
    );
  }

  test('saved manual choice takes priority over system language', () async {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    dispatcher.localesTestValue = [const Locale('ar')];
    addTearDown(dispatcher.clearLocalesTestValue);
    SharedPreferences.setMockInitialValues({'ft_app_locale': 'fr'});
    expect(await AppPreferences.localeCode(), 'fr');
  });

  test(
    'selecting Arabic stores both locale and first-install completion',
    () async {
      SharedPreferences.setMockInitialValues({});

      await AppPreferences.setLocaleCode('ar');

      expect(await AppPreferences.localeCode(), 'ar');
      expect(AppPreferences.localeNotifier.value, 'ar');
      expect(await AppPreferences.hasSelectedLanguage(), isTrue);

      await AppPreferences.setLocaleCode('fr');
      expect(AppPreferences.localeNotifier.value, 'fr');
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
