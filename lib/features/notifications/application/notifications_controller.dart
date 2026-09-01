import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_update/application/app_update_controller.dart';
import '../../home/application/home_controller.dart';
import '../data/notifications_seen_store.dart';
import '../domain/app_notification.dart';

export '../domain/app_notification.dart';

/// The clock the notification window is judged against, so a test can state
/// which day it is instead of depending on the one it runs on.
final notificationsClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Tracks when the list was last opened.
final notificationsSeenProvider =
    NotifierProvider<NotificationsSeenController, NotificationsSeen>(
      NotificationsSeenController.new,
    );

class NotificationsSeenController extends Notifier<NotificationsSeen> {
  @override
  NotificationsSeen build() {
    unawaited(_load());
    return const NotificationsSeen.unknown();
  }

  Future<void> _load() async {
    try {
      final lastOpenedAt = await ref
          .read(notificationsSeenStoreProvider)
          .load();
      if (!ref.mounted) return;
      state = NotificationsSeen(loaded: true, lastOpenedAt: lastOpenedAt);
    } on Object {
      // Preferences that cannot be read are not an error worth showing: the
      // list still works, and nothing is reported as new until they answer.
      if (ref.mounted) state = const NotificationsSeen(loaded: true);
    }
  }

  /// Records that everything currently listed has been looked at.
  Future<void> markOpened() async {
    final moment = ref.read(notificationsClockProvider)().toUtc();
    state = NotificationsSeen(loaded: true, lastOpenedAt: moment);
    try {
      await ref.read(notificationsSeenStoreProvider).markSeenAt(moment);
    } on Object {
      return;
    }
  }
}

/// Everything worth attention, derived from what the app already knows.
final appNotificationsProvider = Provider<List<AppNotification>>((ref) {
  final home = ref.watch(homeControllerProvider);
  final update = ref.watch(appUpdateControllerProvider);
  final now = ref.watch(notificationsClockProvider)();
  return deriveNotifications(
    payments: home.retainedSnapshot?.upcomingPayments ?? const [],
    availableRelease: switch (update) {
      AppUpdateAvailable(:final release) => release,
      // A build already downloading or handed over is not news any more.
      _ => null,
    },
    today: DateTime.utc(now.toUtc().year, now.toUtc().month, now.toUtc().day),
  );
});

/// How many nobody has looked at. Zero until preferences answer, so the dot
/// never appears on a guess.
final unseenNotificationCountProvider = Provider<int>((ref) {
  final seen = ref.watch(notificationsSeenProvider);
  if (!seen.loaded) return 0;
  return countUnseen(ref.watch(appNotificationsProvider), seen.lastOpenedAt);
});

/// Convenience for the one place that only needs to know whether to draw a dot.
final hasUnseenNotificationsProvider = Provider<bool>(
  (ref) => ref.watch(unseenNotificationCountProvider) > 0,
);
