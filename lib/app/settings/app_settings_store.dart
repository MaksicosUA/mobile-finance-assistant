import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../language/app_language.dart';
import 'app_settings.dart';

abstract interface class AppSettingsStore {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

class DiscardingAppSettingsStore implements AppSettingsStore {
  const DiscardingAppSettingsStore();

  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

class SharedPreferencesAppSettingsStore implements AppSettingsStore {
  const SharedPreferencesAppSettingsStore();

  static const _themeKey = 'mfa_theme';
  static const _accentKey = 'mfa_accent';
  static const _privacyKey = 'mfa_privacy';
  static const _languageKey = 'mfa_language';

  @override
  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final themeMode = preferences.getString(_themeKey) == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
    final accentName = preferences.getString(_accentKey);
    final accent = AppAccent.values
        .where((item) => item.name == accentName)
        .firstOrNull;

    return AppSettings(
      themeMode: themeMode,
      accent: accent ?? AppAccent.teal,
      privacyMode: preferences.getBool(_privacyKey) ?? false,
      language: AppLanguage.fromCode(preferences.getString(_languageKey)),
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    final language = settings.language;
    await Future.wait([
      preferences.setString(
        _themeKey,
        settings.themeMode == ThemeMode.dark ? 'dark' : 'light',
      ),
      preferences.setString(_accentKey, settings.accent.name),
      preferences.setBool(_privacyKey, settings.privacyMode),
      if (language == null)
        preferences.remove(_languageKey)
      else
        preferences.setString(_languageKey, language.code),
    ]);
  }
}
