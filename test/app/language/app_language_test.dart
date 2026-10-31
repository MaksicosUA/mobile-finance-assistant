import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/language/app_language.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_store.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the first of the phone\'s languages the app speaks wins', () {
    expect(
      resolveAppLanguage(const [Locale('pl'), Locale('uk', 'UA')]),
      AppLanguage.ukrainian,
    );
    expect(resolveAppLanguage(const [Locale('de', 'AT')]), AppLanguage.german);
  });

  test('a phone in another language gets English', () {
    expect(resolveAppLanguage(const [Locale('pl')]), AppLanguage.english);
    expect(resolveAppLanguage(const []), AppLanguage.english);
  });

  test('every language the app offers has its strings', () {
    final supported = AppLocalizations.supportedLocales
        .map((locale) => locale.languageCode)
        .toSet();

    expect(
      AppLanguage.values.map((language) => language.code).toSet(),
      supported,
    );
  });

  group('the setting', () {
    ProviderContainer container({AppLanguage? chosen}) {
      final container = ProviderContainer(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(
            AppSettings(language: chosen),
          ),
          phoneLanguageProvider.overrideWithValue(AppLanguage.ukrainian),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('with no choice the app follows the phone', () {
      expect(container().read(appLanguageProvider), AppLanguage.ukrainian);
    });

    test('a choice beats the phone', () {
      expect(
        container(chosen: AppLanguage.german).read(appLanguageProvider),
        AppLanguage.german,
      );
    });

    test('a choice can be handed back to the phone', () {
      final subject = container(chosen: AppLanguage.german);

      subject.read(appSettingsControllerProvider.notifier).setLanguage(null);

      expect(subject.read(appSettingsControllerProvider).language, isNull);
      expect(subject.read(appLanguageProvider), AppLanguage.ukrainian);
    });

    test('changing something else keeps the choice', () {
      final subject = container(chosen: AppLanguage.german);

      subject
          .read(appSettingsControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark);

      expect(
        subject.read(appSettingsControllerProvider).language,
        AppLanguage.german,
      );
    });
  });

  group('the store', () {
    const store = SharedPreferencesAppSettingsStore();

    test('remembers a choice', () async {
      SharedPreferences.setMockInitialValues({});

      await store.save(const AppSettings(language: AppLanguage.german));

      expect((await store.load()).language, AppLanguage.german);
    });

    test('forgets a choice handed back to the phone', () async {
      SharedPreferences.setMockInitialValues({'mfa_language': 'de'});

      await store.save(const AppSettings());

      expect((await store.load()).language, isNull);
    });

    test('an install from before languages has made no choice', () async {
      SharedPreferences.setMockInitialValues({'mfa_theme': 'dark'});

      expect((await store.load()).language, isNull);
    });

    test('a language that no longer exists is no choice', () async {
      SharedPreferences.setMockInitialValues({'mfa_language': 'xx'});

      expect((await store.load()).language, isNull);
    });
  });
}
