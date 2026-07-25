import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class AppSwitcherPrivacy {
  Future<void> setProtected(bool enabled);
}

class DiscardingAppSwitcherPrivacy implements AppSwitcherPrivacy {
  const DiscardingAppSwitcherPrivacy();

  @override
  Future<void> setProtected(bool enabled) async {}
}

class PlatformAppSwitcherPrivacy implements AppSwitcherPrivacy {
  const PlatformAppSwitcherPrivacy();

  static const _channel = MethodChannel(
    'com.mobilefinanceassistant/privacy_screen',
  );

  @override
  Future<void> setProtected(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('setProtected', {'enabled': enabled});
  }
}

final appSwitcherPrivacyProvider = Provider<AppSwitcherPrivacy>(
  (ref) => const DiscardingAppSwitcherPrivacy(),
);
