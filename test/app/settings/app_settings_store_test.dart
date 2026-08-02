import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'SharedPreferences stores only the three non-sensitive UI settings',
    () async {
      SharedPreferences.setMockInitialValues({});
      const store = SharedPreferencesAppSettingsStore();

      await store.save(
        const AppSettings(
          themeMode: ThemeMode.dark,
          accent: AppAccent.purple,
          privacyMode: true,
        ),
      );

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getKeys(),
        unorderedEquals({'mfa_theme', 'mfa_accent', 'mfa_privacy'}),
      );
      expect(preferences.getString('mfa_theme'), 'dark');
      expect(preferences.getString('mfa_accent'), 'purple');
      expect(preferences.getBool('mfa_privacy'), isTrue);
    },
  );

  test('settings load ignores unrelated sensitive-looking values', () async {
    SharedPreferences.setMockInitialValues({
      'access_token': 'synthetic-not-a-real-token',
      'home_cache': 'synthetic-not-financial-data',
    });
    const store = SharedPreferencesAppSettingsStore();

    expect(await store.load(), const AppSettings());
  });
}
