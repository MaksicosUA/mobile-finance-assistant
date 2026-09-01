import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// When the notification list was last opened.
///
/// One timestamp, and deliberately nothing else. Recording which notifications
/// were dismissed would mean keeping identifiers of a person's planned costs in
/// preferences; comparing moments needs none of that, and preferences stay what
/// the rules say they are — non-sensitive.
abstract interface class NotificationsSeenStore {
  Future<DateTime?> load();

  Future<void> markSeenAt(DateTime moment);
}

class SharedPreferencesNotificationsSeenStore
    implements NotificationsSeenStore {
  const SharedPreferencesNotificationsSeenStore();

  static const _key = 'mfa_notifications_seen_at';

  @override
  Future<DateTime?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final millis = preferences.getInt(_key);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  @override
  Future<void> markSeenAt(DateTime moment) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_key, moment.toUtc().millisecondsSinceEpoch);
  }
}

/// Used where preferences are unavailable, and by tests that do not care.
class DiscardingNotificationsSeenStore implements NotificationsSeenStore {
  const DiscardingNotificationsSeenStore();

  @override
  Future<DateTime?> load() async => null;

  @override
  Future<void> markSeenAt(DateTime moment) async {}
}

final notificationsSeenStoreProvider = Provider<NotificationsSeenStore>(
  (ref) => const SharedPreferencesNotificationsSeenStore(),
);

/// What is known about the last time the list was opened.
@immutable
final class NotificationsSeen {
  const NotificationsSeen({required this.loaded, this.lastOpenedAt});

  const NotificationsSeen.unknown() : loaded = false, lastOpenedAt = null;

  /// False until preferences have answered. Until then nothing is reported as
  /// unseen: a dot that flashes on every launch is the defect this replaces.
  final bool loaded;
  final DateTime? lastOpenedAt;
}
