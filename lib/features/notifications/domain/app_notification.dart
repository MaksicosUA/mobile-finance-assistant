import 'package:flutter/foundation.dart';

import '../../finance_entry/domain/finance_entry_models.dart';
import '../../home/domain/home_snapshot.dart';

/// How far ahead a payment is worth mentioning.
///
/// A warning that arrives the morning it is due is not a warning.
const Duration paymentWarningWindow = Duration(days: 3);

/// One thing worth someone's attention, **derived** rather than stored.
///
/// Nothing here is written down. A notification is a view over facts that
/// already exist — a payment the server marked overdue, a release the update
/// check found — for the same reason a goal's progress and a plan's `due` are
/// derived (ADR 0018, ADR 0019): a stored copy is a second answer that can
/// disagree with the first.
///
/// What *is* stored is a single timestamp: when the list was last opened.
/// Every notification knows the moment it became true, so "seen" is a
/// comparison rather than a set of identifiers, and nothing about a person's
/// finances ends up in preferences.
@immutable
sealed class AppNotification {
  const AppNotification();

  /// When this became true. Compared against the last time the list was
  /// opened to decide whether anyone has seen it.
  DateTime get noticedAt;
}

@immutable
final class UpdateAvailableNotification extends AppNotification {
  const UpdateAvailableNotification(this.release);

  final AppRelease release;

  @override
  DateTime get noticedAt => DateTime.parse(release.publishedAt).toUtc();
}

@immutable
final class PaymentOverdueNotification extends AppNotification {
  const PaymentOverdueNotification(this.payment);

  final UpcomingPayment payment;

  /// The day it was due. A payment that stays unconfirmed keeps the same
  /// moment, so acknowledging it once is enough.
  @override
  DateTime get noticedAt => payment.dueOn.toUtc();
}

@immutable
final class PaymentDueSoonNotification extends AppNotification {
  const PaymentDueSoonNotification(this.payment);

  final UpcomingPayment payment;

  /// When the warning window opened, not when the payment falls due. That is
  /// what lets the later "overdue" notice count as new: its own moment is the
  /// due date, which is still ahead of this one.
  @override
  DateTime get noticedAt =>
      payment.dueOn.toUtc().subtract(paymentWarningWindow);
}

/// Everything worth attention right now, newest first.
///
/// [today] is the local date the caller considers current, so the window is
/// judged where the user is rather than where the server is.
List<AppNotification> deriveNotifications({
  required List<UpcomingPayment> payments,
  required AppRelease? availableRelease,
  required DateTime today,
}) {
  final notifications = <AppNotification>[
    if (availableRelease != null) UpdateAvailableNotification(availableRelease),
  ];

  final horizon = today.add(paymentWarningWindow);
  for (final payment in payments) {
    // Overdue is the server's decision, not a date this screen recomputes:
    // two definitions of "late" is how two screens start disagreeing.
    if (payment.status == PaymentStatus.overdue) {
      notifications.add(PaymentOverdueNotification(payment));
    } else if (!payment.dueOn.toUtc().isAfter(horizon)) {
      notifications.add(PaymentDueSoonNotification(payment));
    }
  }

  notifications.sort((a, b) => b.noticedAt.compareTo(a.noticedAt));
  return List<AppNotification>.unmodifiable(notifications);
}

/// How many of [notifications] nobody has looked at yet.
int countUnseen(List<AppNotification> notifications, DateTime? lastOpenedAt) {
  if (lastOpenedAt == null) return notifications.length;
  return notifications
      .where((item) => item.noticedAt.isAfter(lastOpenedAt))
      .length;
}
