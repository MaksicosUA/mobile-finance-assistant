import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../language/app_language.dart';
import '../privacy/app_switcher_privacy.dart';
import 'app_settings.dart';
import 'app_settings_store.dart';

final initialAppSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

final appSettingsStoreProvider = Provider<AppSettingsStore>(
  (ref) => const DiscardingAppSettingsStore(),
);

final appSettingsControllerProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

/// The language the phone asks for, among the ones the app speaks.
final phoneLanguageProvider = Provider<AppLanguage>((ref) {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  return resolveAppLanguage(binding.platformDispatcher.locales);
});

/// The country the phone says it is in, when one of its languages names one.
final phoneRegionProvider = Provider<String?>((ref) {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  for (final locale in binding.platformDispatcher.locales) {
    final region = locale.countryCode;
    if (region != null && region.isNotEmpty) return region;
  }
  return null;
});

/// The language the app is in: the person's choice, or else the phone's.
final appLanguageProvider = Provider<AppLanguage>((ref) {
  final chosen = ref.watch(
    appSettingsControllerProvider.select((settings) => settings.language),
  );
  return chosen ?? ref.watch(phoneLanguageProvider);
});

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialAppSettingsProvider);

  void setThemeMode(ThemeMode themeMode) {
    _update(state.copyWith(themeMode: themeMode));
  }

  void setAccent(AppAccent accent) {
    _update(state.copyWith(accent: accent));
  }

  void setPrivacyMode(bool enabled) {
    _update(state.copyWith(privacyMode: enabled));
  }

  /// Null hands the choice back to the phone.
  void setLanguage(AppLanguage? language) {
    _update(state.withLanguage(language));
  }

  void togglePrivacyMode() {
    setPrivacyMode(!state.privacyMode);
  }

  void _update(AppSettings settings) {
    final privacyChanged = settings.privacyMode != state.privacyMode;
    state = settings;
    unawaited(ref.read(appSettingsStoreProvider).save(settings));
    if (privacyChanged) {
      unawaited(
        ref.read(appSwitcherPrivacyProvider).setProtected(settings.privacyMode),
      );
    }
  }
}
