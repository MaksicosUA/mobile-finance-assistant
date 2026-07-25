import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
