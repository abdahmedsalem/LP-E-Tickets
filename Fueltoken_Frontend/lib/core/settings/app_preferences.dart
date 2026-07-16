import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences._();

  static const _kLocale = 'ft_app_locale';
  static const _kHasSelectedLanguage = 'ft_has_selected_language';
  static const _kDark = 'ft_app_dark_mode';
  static const _kHasSeenOnboarding = 'ft_has_seen_onboarding';

  /// Langues supportées par l’app (UI + préférences) : français et arabe uniquement.
  static const String defaultLocaleCode = 'fr';

  static Future<String> localeCode() async {
    final p = await SharedPreferences.getInstance();
    var stored = p.getString(_kLocale);
    if (stored == null || stored.isEmpty) {
      return defaultLocaleCode;
    }
    if (stored == 'en') {
      await p.setString(_kLocale, 'fr');
      return 'fr';
    }
    switch (stored) {
      case 'ar':
      case 'fr':
        return stored;
      default:
        await p.setString(_kLocale, defaultLocaleCode);
        return defaultLocaleCode;
    }
  }

  static Future<void> setLocaleCode(String code) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLocale, code);
    await p.setBool(_kHasSelectedLanguage, true);
  }

  static Future<bool> hasSelectedLanguage() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kHasSelectedLanguage) == true) return true;

    // Existing installations already containing a supported locale must not
    // be sent through the first-installation flow after an app update.
    final stored = p.getString(_kLocale);
    return stored == 'fr' || stored == 'ar';
  }

  static Future<bool> darkMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kDark) ?? false;
  }

  static Future<void> setDarkMode(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDark, v);
  }

  static Future<bool> hasSeenOnboarding() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kHasSeenOnboarding) ?? false;
  }

  static Future<void> setHasSeenOnboarding(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHasSeenOnboarding, value);
  }

  static Locale localeFromCode(String code) {
    switch (code) {
      case 'ar':
        return const Locale('ar');
      case 'fr':
      default:
        return const Locale('fr');
    }
  }

  static String labelForCode(String code) {
    switch (code) {
      case 'ar':
        return 'العربية';
      case 'fr':
      default:
        return 'Français';
    }
  }
}
