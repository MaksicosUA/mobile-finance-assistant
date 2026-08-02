import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/privacy/app_switcher_privacy.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';

void main() {
  test('app-switcher protection follows only privacy preference changes', () {
    final privacy = _RecordingAppSwitcherPrivacy();
    final container = ProviderContainer(
      overrides: [appSwitcherPrivacyProvider.overrideWithValue(privacy)],
    );
    addTearDown(container.dispose);
    final controller = container.read(appSettingsControllerProvider.notifier);

    controller.setAccent(AppAccent.blue);
    expect(privacy.values, isEmpty);

    controller.setPrivacyMode(true);
    controller.setPrivacyMode(false);

    expect(privacy.values, [true, false]);
  });
}

class _RecordingAppSwitcherPrivacy implements AppSwitcherPrivacy {
  final values = <bool>[];

  @override
  Future<void> setProtected(bool enabled) async {
    values.add(enabled);
  }
}
