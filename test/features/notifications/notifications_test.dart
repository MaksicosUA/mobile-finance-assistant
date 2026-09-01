import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/features/notifications/application/notifications_controller.dart';
import 'package:mobile_finance_assistant/features/notifications/data/notifications_seen_store.dart';
import 'package:mobile_finance_assistant/features/notifications/presentation/notifications_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

final _today = DateTime.utc(2026, 9, 1);

UpcomingPayment _payment({
  String id = 'plan-1',
  String title = 'Аренда',
  required DateTime dueOn,
  PaymentStatus status = PaymentStatus.scheduled,
  String amount = '800.00',
}) {
  return UpcomingPayment(
    id: id,
    title: title,
    dueOn: dueOn,
    dueAt: null,
    amount: Money(amount: amount, currency: 'EUR'),
    status: status,
  );
}

AppRelease _release() => AppRelease.fromJson(<String, Object?>{
  'versionCode': 3000200,
  'versionName': '0.1.17.3000200',
  'sizeBytes': 59 * 1024 * 1024,
  'sha256': 'b' * 64,
  'notes': null,
  'publishedAt': '2026-08-30T10:00:00Z',
});

void main() {
  // --- what is worth attention ----------------------------------------------

  test('a payment the server calls overdue is reported', () {
    final notifications = deriveNotifications(
      payments: [
        _payment(
          dueOn: DateTime.utc(2026, 8, 28),
          status: PaymentStatus.overdue,
        ),
      ],
      availableRelease: null,
      today: _today,
    );

    expect(notifications.single, isA<PaymentOverdueNotification>());
  });

  test('a payment inside the warning window is reported early', () {
    final notifications = deriveNotifications(
      payments: [_payment(dueOn: DateTime.utc(2026, 9, 3))],
      availableRelease: null,
      today: _today,
    );

    expect(notifications.single, isA<PaymentDueSoonNotification>());
  });

  test('a payment beyond the window is not mentioned yet', () {
    // A warning that fires a month early is noise, not a warning.
    final notifications = deriveNotifications(
      payments: [_payment(dueOn: DateTime.utc(2026, 9, 20))],
      availableRelease: null,
      today: _today,
    );

    expect(notifications, isEmpty);
  });

  test('overdue wins over the window rather than producing two notices', () {
    final notifications = deriveNotifications(
      payments: [
        _payment(
          dueOn: DateTime.utc(2026, 9, 1),
          status: PaymentStatus.overdue,
        ),
      ],
      availableRelease: null,
      today: _today,
    );

    expect(notifications, hasLength(1));
    expect(notifications.single, isA<PaymentOverdueNotification>());
  });

  test('an available update is reported', () {
    final notifications = deriveNotifications(
      payments: const [],
      availableRelease: _release(),
      today: _today,
    );

    expect(notifications.single, isA<UpdateAvailableNotification>());
  });

  test('the newest is first', () {
    final notifications = deriveNotifications(
      payments: [
        _payment(
          dueOn: DateTime.utc(2026, 9, 1),
          status: PaymentStatus.overdue,
        ),
      ],
      availableRelease: _release(),
      today: _today,
    );

    expect(notifications.first, isA<PaymentOverdueNotification>());
    expect(notifications.last, isA<UpdateAvailableNotification>());
  });

  // --- what counts as seen ---------------------------------------------------

  test('nothing has been seen before the list was ever opened', () {
    final notifications = deriveNotifications(
      payments: const [],
      availableRelease: _release(),
      today: _today,
    );

    expect(countUnseen(notifications, null), 1);
  });

  test('opening the list after a notice appeared marks it seen', () {
    final notifications = deriveNotifications(
      payments: const [],
      availableRelease: _release(),
      today: _today,
    );

    expect(countUnseen(notifications, DateTime.utc(2026, 8, 31)), 0);
    expect(countUnseen(notifications, DateTime.utc(2026, 8, 29)), 1);
  });

  test('seeing the early warning does not silence the overdue notice', () {
    // The whole reason a notification carries the moment it became true: the
    // later notice about the same payment has a later moment, so it is new.
    final dueOn = DateTime.utc(2026, 9, 4);
    final warned = deriveNotifications(
      payments: [_payment(dueOn: dueOn)],
      availableRelease: null,
      today: _today,
    );
    final seenAt = DateTime.utc(2026, 9, 1, 12);
    expect(countUnseen(warned, seenAt), 0, reason: 'the warning was read');

    final overdue = deriveNotifications(
      payments: [_payment(dueOn: dueOn, status: PaymentStatus.overdue)],
      availableRelease: null,
      today: dueOn,
    );
    expect(countUnseen(overdue, seenAt), 1);
  });

  // --- the screen ------------------------------------------------------------

  testWidgets('an empty list says so instead of showing a blank page', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const Key('notifications-empty')), findsOneWidget);
  });

  testWidgets('a payment notice masks its amount in privacy mode', (
    tester,
  ) async {
    await _pump(
      tester,
      payments: [
        _payment(
          dueOn: DateTime.utc(2026, 9, 1),
          status: PaymentStatus.overdue,
        ),
      ],
      privacy: true,
    );

    // A notification is not an exception to privacy mode.
    expect(find.textContaining('800'), findsNothing);
    expect(find.textContaining('••••'), findsOneWidget);
  });

  testWidgets('opening the list records the moment it was seen', (
    tester,
  ) async {
    final store = _RecordingSeenStore();
    await _pump(tester, release: _release(), seenStore: store);

    expect(store.recorded, hasLength(1));
  });

  testWidgets('a notice names what it is about', (tester) async {
    await _pump(
      tester,
      payments: [
        _payment(
          title: 'Аренда',
          dueOn: DateTime.utc(2026, 8, 28),
          status: PaymentStatus.overdue,
        ),
      ],
    );

    expect(find.textContaining('Аренда'), findsOneWidget);
    expect(find.byKey(const Key('notifications-list')), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  List<UpcomingPayment> payments = const [],
  AppRelease? release,
  bool privacy = false,
  NotificationsSeenStore? seenStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsClockProvider.overrideWithValue(() => _today),
        notificationsSeenStoreProvider.overrideWithValue(
          seenStore ?? const DiscardingNotificationsSeenStore(),
        ),
        initialAppSettingsProvider.overrideWithValue(
          AppSettings(privacyMode: privacy),
        ),
        appNotificationsProvider.overrideWith(
          (ref) => deriveNotifications(
            payments: payments,
            availableRelease: release,
            today: _today,
          ),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(AppAccent.teal),
        home: NotificationsPage(
          onOpenProfile: () {},
          onOpenPlannedCosts: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _RecordingSeenStore implements NotificationsSeenStore {
  final List<DateTime> recorded = [];

  @override
  Future<DateTime?> load() async => null;

  @override
  Future<void> markSeenAt(DateTime moment) async => recorded.add(moment);
}
