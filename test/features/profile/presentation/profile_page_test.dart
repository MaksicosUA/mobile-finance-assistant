import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/app_version.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/profile/presentation/profile_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('the profile names who is signed in and how', (tester) async {
    await _pumpPage(tester, repository: _FakeRepository());

    expect(find.byKey(const Key('profile-name')), findsOneWidget);
    expect(find.text('Синтетический Пользователь'), findsOneWidget);
    // The address matters because a user has to be able to tell which account
    // they are in, and the encrypted session stores only tokens.
    expect(find.text('owner@example.test'), findsOneWidget);
  });

  testWidgets('the account facts are here and no balance is', (tester) async {
    await _pumpPage(tester, repository: _FakeRepository());

    expect(find.text('EUR'), findsOneWidget);
    expect(find.text('Europe/Berlin'), findsOneWidget);
    // A second surface reporting money is a second thing that can disagree
    // with the authoritative projection.
    expect(find.textContaining('€'), findsNothing);
    expect(find.textContaining('1 240'), findsNothing);
  });

  testWidgets('the opening date is readable without opening its screen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpPage(tester, repository: _FakeRepository());

    expect(find.byKey(const Key('profile-opening-date')), findsOneWidget);
    // Built from the localization rather than typed out: the Russian long date
    // separates its parts with non-breaking spaces, and a literal here would
    // be a test that fails on an invisible character.
    final context = tester.element(find.byKey(const Key('profile-page')));
    final expected = AppLocalizations.of(
      context,
    ).profileOpeningDateValue(DateTime(2026, 6, 1));
    expect(expected, contains('2026'));
    expect(find.text(expected), findsOneWidget);
    // Spoken as well as shown: the date is part of what the action is.
    expect(
      find.bySemanticsLabel(
        'Дата начала учёта. $expected. '
        'Разрешить операции за более ранний период',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('a registered user without an account is not an error', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository(account: false));

    expect(find.byKey(const Key('profile-no-account')), findsOneWidget);
    expect(find.byKey(const Key('profile-failure')), findsNothing);
    // The identity is still known, so it is still shown.
    expect(find.byKey(const Key('profile-name')), findsOneWidget);
  });

  testWidgets('every action moved out of settings is reachable here', (
    tester,
  ) async {
    final opened = <String>[];
    await _pumpPage(
      tester,
      repository: _FakeRepository(),
      onCorrectOpeningDate: () => opened.add('baseline'),
      onPlanCost: () => opened.add('plan'),
      onManageCategories: () => opened.add('categories'),
      onOperationHistory: () => opened.add('operations'),
    );

    for (final key in const [
      'profile-opening-date',
      'profile-plan-cost',
      'profile-categories',
      'profile-operation-history',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }

    expect(opened, ['baseline', 'plan', 'categories', 'operations']);
  });

  testWidgets('appearance lives here now, not behind a gear on Home', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository());

    await tester.scrollUntilVisible(
      find.byKey(const Key('theme-dark')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const Key('theme-light')), findsOneWidget);
    expect(find.byKey(const Key('accent-teal')), findsOneWidget);
    expect(find.byKey(const Key('settings-privacy-toggle')), findsOneWidget);
  });

  testWidgets('the installed build is written down', (tester) async {
    await _pumpPage(tester, repository: _FakeRepository());

    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-version')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    // It exists because working out which build was on the phone repeatedly
    // meant reading a manifest instead of the app.
    expect(find.text('Версия $appVersion'), findsOneWidget);
  });

  testWidgets('signing out asks first, then signs out', (tester) async {
    var signedOut = 0;
    await _pumpPage(
      tester,
      repository: _FakeRepository(),
      onSignOut: () async => signedOut += 1,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-sign-out')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await tester.pumpAndSettle();
    expect(signedOut, 0);

    await tester.tap(find.byKey(const Key('confirm-sign-out')));
    await tester.pumpAndSettle();

    expect(signedOut, 1);
  });

  testWidgets('a failed profile keeps the rest of the screen usable', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(failure: FinanceEntryFailureKind.timeout),
    );

    expect(find.byKey(const Key('profile-failure')), findsOneWidget);
    // Block independence: losing the identity must not take the actions,
    // appearance, sign-out, or the version down with it.
    expect(find.byKey(const Key('profile-categories')), findsOneWidget);
    expect(find.byKey(const Key('profile-sign-out')), findsOneWidget);
    // The action still works, it just cannot say what the date currently is.
    expect(find.textContaining('Сейчас'), findsNothing);
  });

  testWidgets('a retry after a failure loads the profile', (tester) async {
    final repository = _FakeRepository(
      failure: FinanceEntryFailureKind.timeout,
    );
    await _pumpPage(tester, repository: repository);

    repository.failure = null;
    await tester.tap(find.byKey(const Key('profile-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-name')), findsOneWidget);
  });

  testWidgets('an expired session asks for a sign-in instead of an error', (
    tester,
  ) async {
    var signInRequests = 0;
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        failure: FinanceEntryFailureKind.unauthenticated,
      ),
      onSignInRequested: () async => signInRequests += 1,
      // The waiting spinner never stops on its own, so settling would hang.
      settle: false,
    );

    expect(signInRequests, 1);
    expect(find.byKey(const Key('profile-failure')), findsNothing);
  });

  testWidgets('the screen fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(),
      surface: const Size(360, 800),
      textScale: 2,
    );

    for (final key in const [
      'profile-name',
      'profile-opening-date',
      'profile-sign-out',
      'profile-version',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('a pull re-reads the profile', (tester) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    // Pulled from the top of the screen, the way the gesture is made: the
    // indicator arms itself against the viewport, and this one is tall.
    await tester.flingFrom(const Offset(195, 120), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(repository.readCalls, 2);
    expect(find.byKey(const Key('profile-version')), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeRepository repository,
  Future<void> Function()? onSignInRequested,
  VoidCallback? onCorrectOpeningDate,
  VoidCallback? onPlanCost,
  VoidCallback? onManageCategories,
  VoidCallback? onOperationHistory,
  Future<void> Function()? onSignOut,
  Size surface = const Size(390, 1600),
  double textScale = 1,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeEntryRepositoryProvider.overrideWithValue(repository),
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
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
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: Scaffold(
          body: ProfilePage(
            onSignInRequested: onSignInRequested ?? () async {},
            onCorrectOpeningDate: onCorrectOpeningDate ?? () {},
            onPlanCost: onPlanCost ?? () {},
            onManageCategories: onManageCategories ?? () {},
            onOperationHistory: onOperationHistory ?? () {},
            onSignOut: onSignOut ?? () async {},
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

class _FakeRepository implements FinanceEntryRepositoryClient {
  @override
  Future<FinanceEntryResult<AppUpdateManifest>> readAppUpdate() =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<void>> downloadAppRelease({
    required String savePath,
    required void Function(int received, int total) onProgress,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceCreated>>
  createPlannedCostRecurrence(PlannedCostRecurrenceDraft draft) =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceList>>
  listPlannedCostRecurrences() => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceEnded>>
  endPlannedCostRecurrence(
    String recurrenceId,
    EndPlannedCostRecurrenceCommand command,
  ) => throw UnimplementedError();

  _FakeRepository({this.failure, this.account = true});

  FinanceEntryFailureKind? failure;
  final bool account;
  int readCalls = 0;

  @override
  Future<FinanceEntryResult<UserProfile>> readProfile() async {
    readCalls += 1;
    final kind = failure;
    if (kind != null) {
      return FinanceEntryFailureResult<UserProfile>(
        FinanceEntryFailure(kind: kind, requestId: 'req_synthetic'),
      );
    }
    return FinanceEntrySuccess<UserProfile>(
      requestId: 'req_synthetic',
      value: UserProfile(
        displayName: 'Синтетический Пользователь',
        email: 'owner@example.test',
        account: account
            ? const ProfileAccountFacts(
                currency: 'EUR',
                canonicalTimezone: 'Europe/Berlin',
                openingBalanceOn: '2026-06-01',
              )
            : null,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
