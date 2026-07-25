import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/privacy/app_switcher_privacy.dart';
import 'app/settings/app_settings_controller.dart';
import 'app/settings/app_settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const settingsStore = SharedPreferencesAppSettingsStore();
  final initialSettings = await settingsStore.load();
  const appSwitcherPrivacy = PlatformAppSwitcherPrivacy();
  await appSwitcherPrivacy.setProtected(initialSettings.privacyMode);

  runApp(
    ProviderScope(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(initialSettings),
        appSettingsStoreProvider.overrideWithValue(settingsStore),
        appSwitcherPrivacyProvider.overrideWithValue(appSwitcherPrivacy),
      ],
      child: const FinanceApp(),
    ),
  );
}
