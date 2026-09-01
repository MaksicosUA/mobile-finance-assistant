import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How often the app asks the server about itself on its own.
///
/// A week, and only at start-up: not a background job, no scheduler, no work
/// while the app is closed. One small request on a launch that happens to be a
/// week after the last one.
const Duration updateCheckInterval = Duration(days: 7);

/// When the app last got an answer about updates.
///
/// A timestamp, and nothing else — it says nothing about a person or their
/// money, so preferences remain what the rules say they are.
abstract interface class AppUpdateScheduleStore {
  Future<DateTime?> lastCheckedAt();

  Future<void> recordCheckedAt(DateTime moment);
}

class SharedPreferencesAppUpdateScheduleStore
    implements AppUpdateScheduleStore {
  const SharedPreferencesAppUpdateScheduleStore();

  static const _key = 'mfa_update_checked_at';

  @override
  Future<DateTime?> lastCheckedAt() async {
    final preferences = await SharedPreferences.getInstance();
    final millis = preferences.getInt(_key);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  @override
  Future<void> recordCheckedAt(DateTime moment) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_key, moment.toUtc().millisecondsSinceEpoch);
  }
}

class DiscardingAppUpdateScheduleStore implements AppUpdateScheduleStore {
  const DiscardingAppUpdateScheduleStore();

  @override
  Future<DateTime?> lastCheckedAt() async => null;

  @override
  Future<void> recordCheckedAt(DateTime moment) async {}
}

final appUpdateScheduleStoreProvider = Provider<AppUpdateScheduleStore>(
  (ref) => const SharedPreferencesAppUpdateScheduleStore(),
);
