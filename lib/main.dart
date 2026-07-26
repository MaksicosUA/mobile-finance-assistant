import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/privacy/app_switcher_privacy.dart';
import 'app/settings/app_settings_controller.dart';
import 'app/settings/app_settings_store.dart';
import 'core/network/api_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const settingsStore = SharedPreferencesAppSettingsStore();
  final initialSettings = await settingsStore.load();
  const appSwitcherPrivacy = PlatformAppSwitcherPrivacy();
  // Authentication fields may contain personal data. Network builds begin
  // protected and AuthGate restores the user's privacy preference only after
  // a valid local session is established.
  await appSwitcherPrivacy.setProtected(
    isNetworkBackendConfigured || initialSettings.privacyMode,
  );

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
