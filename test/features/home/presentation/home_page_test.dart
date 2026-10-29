import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/app.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/application/home_session_recovery.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/features/home/presentation/home_page.dart';
import 'package:mobile_finance_assistant/features/voice_entry/application/voice_entry_controller.dart';
import 'package:mobile_finance_assistant/features/voice_entry/application/waiting_phrases_controller.dart';
import 'package:mobile_finance_assistant/features/voice_entry/domain/waiting_phrase.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

import '../../../support/home_contract_fixture.dart';

void main() {
  testWidgets('shows loading while the repository request is pending', (
    tester,
  ) async {
    final repository = _CompleterHomeRepository();
    await _pumpApp(tester, repository: repository);

    expect(find.byKey(const Key('home-loading')), findsOneWidget);
    expect(find.byKey(const Key('nav-home')), findsOneWidget);

    repository.complete(
      HomeFirstUseResult(
        HomeFirstUseData(
          userName: 'Максим',
          availableActions: {HomeAction.voiceEntry},
        ),
      ),
    );
    await tester.pump();
  });

  testWidgets('renders populated Home and opens the entry route', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('populated.json'),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('home-populated')), findsOneWidget);
    expect(find.text('3 240,50 €'), findsOneWidget);
    expect(find.byKey(const Key('upcoming-payments')), findsOneWidget);
    expect(find.byKey(const Key('payment-payment_fixture_3')), findsOneWidget);

    // Home answers "how much do I have" and "record something". The monthly
    // totals, the chart, the goal and the operation list moved to Analytics
    // and Goals; the API still sends them, this screen just stops drawing
    // them.
    expect(find.textContaining('Итоги за июль'), findsNothing);
    expect(find.byKey(const Key('spending-chart')), findsNothing);
    expect(find.byKey(const Key('primary-goal')), findsNothing);
    expect(find.byKey(const Key('recent-transactions')), findsNothing);

    // The fixture build has no entry screen for a spoken sentence to land
    // on, so the microphone is drawn and cannot be pressed.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('voice-entry-cta')))
          .onPressed,
      isNull,
    );
    expect(find.text('Написать фразой'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-entry-cta')));
    await tester.pump();

    // This is the fixture build, which has no authenticated backend behind
    // the entry screen, so the route it leaves Home for is the stub. What
    // matters here is that Home no longer stops at a voice placeholder.
    expect(find.text('Голосовой ввод'), findsNothing);
    expect(find.byKey(const Key('home-populated')), findsNothing);
  });

  // Several wallets, one currency each (ADR 0029).
  testWidgets('other wallets are listed beside the card and never summed', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('wallets.json'),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('home-wallets')), findsOneWidget);
    // The card still states the default wallet, in its own currency.
    expect(find.text('3 240,50 €'), findsOneWidget);
    // The other wallet states its own, and nowhere is a total drawn: adding
    // euro to hryvnia would need a rate the product does not have.
    expect(find.text('Гривна'), findsOneWidget);
    expect(find.textContaining('4 800,00'), findsOneWidget);
    // The card is named after the wallet it shows — the name the owner gave
    // it — and only there: it is not repeated in the list beneath.
    expect(
      find.descendant(
        of: find.byKey(const Key('balance-card')),
        matching: find.text('Основной'),
      ),
      findsOneWidget,
    );
    expect(find.text('Основной'), findsOneWidget);
    // It used to say «Общий баланс» over «Все активные счета» while showing one
    // wallet of several, which is how an exchange came to look like a loss.
    expect(find.text('Общий баланс'), findsNothing);
    expect(find.text('Все активные счета'), findsNothing);
  });

  testWidgets('a snapshot without wallets claims no total either', (
    tester,
  ) async {
    // A cached snapshot from before wallets existed carries no names. The card
    // then says only what is certain: it is a balance.
    await _pumpApp(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('populated.json'),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('balance-card')),
        matching: find.text('Баланс'),
      ),
      findsOneWidget,
    );
    expect(find.text('Общий баланс'), findsNothing);
    expect(find.text('Все активные счета'), findsNothing);
  });

  testWidgets('a profile with one wallet shows no list', (tester) async {
    await _pumpApp(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('populated.json'),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('home-wallets')), findsNothing);
  });

  testWidgets('privacy mode masks a wallet like everything else', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('wallets.json'),
      ),
      settings: const AppSettings(privacyMode: true),
    );
    await tester.pump();

    expect(find.byKey(const Key('home-wallets')), findsOneWidget);
    expect(find.textContaining('4 800'), findsNothing);
  });

  testWidgets(
    'mounted Home reloads after a same-account session epoch advance',
    (tester) async {
      final snapshot = loadHomeFixtureSnapshotSync('populated.json');
      final rotatedSessionFetch = Completer<HomeRepositoryResult>();
      final repository = _SequenceHomeRepository([
        HomeDataResult(snapshot),
        rotatedSessionFetch.future,
      ]);

      await _pumpHomePage(
        tester,
        repository: repository,
        recovery: const ScenarioHomeSessionRecovery(),
        onSignOutRequested: _ignore,
      );
      await tester.pumpAndSettle();

      expect(repository.calls, 1);
      expect(find.byKey(const Key('home-populated')), findsOneWidget);

      final context = tester.element(find.byKey(const Key('home-page')));
      final container = ProviderScope.containerOf(context, listen: false);
      container.read(authSessionEpochProvider.notifier).advance();
      await tester.pump();
      await tester.pump();

      expect(repository.calls, 2);
      expect(find.byKey(const Key('home-loading')), findsOneWidget);

      rotatedSessionFetch.complete(HomeDataResult(snapshot));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-loading')), findsNothing);
      expect(find.byKey(const Key('home-populated')), findsOneWidget);
      expect(repository.calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  // ADR 0031: the large action is the microphone; writing is the quieter one.
  testWidgets('the microphone is the large action, writing the second', (
    tester,
  ) async {
    var voiceRequests = 0;
    var entryRequests = 0;
    await _pumpHomePage(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('populated.json'),
      ),
      recovery: const ScenarioHomeSessionRecovery(),
      onSignOutRequested: _ignore,
      onVoicePressed: () => voiceRequests += 1,
      onEntryPressed: () => entryRequests += 1,
    );
    await tester.pump();

    final voice = tester.getSize(find.byKey(const Key('voice-entry-cta')));
    final written = tester.getSize(find.byKey(const Key('quick-entry-cta')));
    expect(voice.height, greaterThanOrEqualTo(72));
    expect(voice.height, greaterThan(written.height));
    expect(find.bySemanticsLabel('Добавить операцию голосом'), findsOneWidget);

    await tester.tap(find.byKey(const Key('voice-entry-cta')));
    await tester.tap(find.byKey(const Key('quick-entry-cta')));
    expect(voiceRequests, 1);
    expect(entryRequests, 1);
  });

  // ADR 0032: phrases said without a connection are counted on Home, and
  // their words are shown nowhere here.
  testWidgets('phrases said offline are counted, and open from Home', (
    tester,
  ) async {
    var opened = 0;
    await _pumpHomePage(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('populated.json'),
      ),
      recovery: const ScenarioHomeSessionRecovery(),
      onSignOutRequested: _ignore,
      onWaitingPhrasesPressed: () => opened += 1,
      waiting: [
        for (final index in [1, 2])
          WaitingPhrase(
            id: '00000000-0000-4000-8000-00000000000$index',
            text: 'Заплатил 80 за свет',
            saidAt: DateTime.utc(2026, 7, 10, 18),
            saidInTimezone: 'Europe/Berlin',
          ),
      ],
    );
    await tester.pump();

    expect(find.text('Ждут разбора: 2'), findsOneWidget);
    expect(find.textContaining('за свет'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('ждут разбора: 2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('waiting-phrases-notice')));
    expect(opened, 1);
  });

  testWidgets('with nothing waiting, Home says nothing about it', (
    tester,
  ) async {
    await _pumpHomePage(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('populated.json'),
      ),
      recovery: const ScenarioHomeSessionRecovery(),
      onSignOutRequested: _ignore,
      onWaitingPhrasesPressed: _ignore,
    );
    await tester.pump();

    expect(find.byKey(const Key('waiting-phrases-notice')), findsNothing);
  });

  testWidgets('an open recogniser cannot be opened a second time', (
    tester,
  ) async {
    var voiceRequests = 0;
    await _pumpHomePage(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('populated.json'),
      ),
      recovery: const ScenarioHomeSessionRecovery(),
      onSignOutRequested: _ignore,
      onVoicePressed: () => voiceRequests += 1,
      listening: true,
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('voice-entry-cta')));
    expect(voiceRequests, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders the first-use empty state with one voice CTA', (
    tester,
  ) async {
    await _pumpApp(tester, repository: const _ValueHomeRepository(null));
    await tester.pump();

    expect(find.byKey(const Key('home-empty')), findsOneWidget);
    expect(find.byKey(const Key('balance-card')), findsNothing);
    expect(find.byKey(const Key('quick-entry-cta')), findsOneWidget);
  });

  testWidgets('first-use Home exposes a distinct manual account action', (
    tester,
  ) async {
    var manualRequests = 0;
    await _pumpHomePage(
      tester,
      repository: const _ValueHomeRepository(null),
      recovery: const ScenarioHomeSessionRecovery(),
      onSignOutRequested: _ignore,
      onManualEntryPressed: () => manualRequests += 1,
    );
    await tester.pump();

    expect(find.byKey(const Key('quick-entry-cta')), findsOneWidget);
    expect(find.byKey(const Key('home-empty-manual-entry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-empty-manual-entry')));
    expect(manualRequests, 1);
  });

  testWidgets('masks all visible amounts from the balance privacy action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(430, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpApp(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('populated.json'),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('privacy-toggle')));
    await tester.pump();

    expect(find.text('•••••• €'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('••••••')), findsWidgets);

    for (final rawValue in [
      '3 240,50',
      '182,40',
      '5,96',
      '1 930,00',
      '847,20',
      '1 082,80',
      '3 200,00',
      '10 000,00',
      '1 360,00',
      '530,00',
      '39,99',
      '74,00',
      '38,00',
      '55,00',
    ]) {
      expect(find.textContaining(rawValue), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(rawValue))),
        findsNothing,
      );
    }
    semantics.dispose();
  });

  testWidgets('supports a 360 dp dark layout at 200 percent text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpApp(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('populated.json'),
      ),
      settings: const AppSettings(themeMode: ThemeMode.dark),
    );
    await tester.pump();

    final context = tester.element(find.byKey(const Key('home-page')));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const Key('home-page')),
      const Offset(0, -1400),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('upcoming-payments')), findsOneWidget);
  });

  testWidgets('renders nullable goal and empty blocks from contract fixture', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('empty_lists.json'),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('home-populated')), findsOneWidget);
    expect(find.text('Ближайших платежей нет'), findsOneWidget);
    // The goal, the chart and the operation list report their own empty states
    // on the screens they moved to.
    expect(find.byKey(const Key('goal-unavailable')), findsNothing);
    expect(find.text('Пока недостаточно данных для графика'), findsNothing);
    expect(find.text('Подтверждённых операций пока нет'), findsNothing);
  });

  testWidgets('static Home respects reduced-motion accessibility setting', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpApp(
      tester,
      repository: _ValueHomeRepository(
        loadHomeFixtureSnapshotSync('populated.json'),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('balance-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial failure replaces only its failed Home block', (
    tester,
  ) async {
    final snapshot = loadHomeFixtureSnapshotSync('populated.json');
    await _pumpApp(
      tester,
      repository: _ResultHomeRepository(
        HomePartialResult(
          snapshot: snapshot,
          blockFailures: const {
            HomeBlock.primaryGoal: HomeBlockFailure(
              code: 'goal_unavailable',
              requestId: 'req_goal_widget',
            ),
          },
        ),
      ),
    );
    await tester.pump();

    // The banner still says the snapshot is partial, because it is. What
    // changed is that the failed block belongs to another screen now, so Home
    // has nothing to replace and keeps all three of its own.
    expect(find.byKey(const Key('partial-banner')), findsOneWidget);
    expect(find.byKey(const Key('balance-card')), findsOneWidget);
    expect(find.byKey(const Key('quick-entry-cta')), findsOneWidget);
    expect(find.byKey(const Key('upcoming-payments')), findsOneWidget);
    expect(find.byKey(const Key('goal-unavailable')), findsNothing);
  });

  testWidgets(
    'partial opening keeps total and masks balance delta privacy semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpApp(
        tester,
        repository: _ResultHomeRepository(
          HomePartialResult(
            snapshot: loadHomeFixtureSnapshotSync('populated.json'),
            blockFailures: const {
              HomeBlock.balanceDelta: HomeBlockFailure(
                code: 'balance_delta_percent_unavailable_partial_period',
                requestId: 'req_balance_delta_widget',
              ),
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('balance-card')), findsOneWidget);
      expect(find.byKey(const Key('balance-unavailable')), findsNothing);
      expect(find.text('3 240,50 €'), findsOneWidget);
      expect(
        find.byKey(const Key('balance-delta-unavailable')),
        findsOneWidget,
      );
      expect(find.text('Динамика за месяц недоступна'), findsOneWidget);
      expect(find.textContaining('182,40'), findsNothing);
      expect(find.textContaining('5,96'), findsNothing);

      await tester.tap(find.byKey(const Key('privacy-toggle')));
      await tester.pump();

      expect(find.text('•••••• €'), findsWidgets);
      for (final rawValue in ['3 240,50', '182,40', '5,96']) {
        expect(find.textContaining(rawValue), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(rawValue))),
          findsNothing,
        );
      }
      expect(
        find.bySemanticsLabel(RegExp('Динамика за месяц недоступна')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  for (final partialCase in <(HomeBlock, Key)>[
    (HomeBlock.balance, const Key('balance-unavailable')),
    (HomeBlock.upcomingPayments, const Key('upcoming-payments-unavailable')),
  ]) {
    testWidgets('isolates ${partialCase.$1.name} block failure', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        repository: _ResultHomeRepository(
          HomePartialResult(
            snapshot: loadHomeFixtureSnapshotSync('populated.json'),
            blockFailures: {
              partialCase.$1: const HomeBlockFailure(
                code: 'synthetic_unavailable',
                requestId: 'req_block_widget',
              ),
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(partialCase.$2), findsOneWidget);
      expect(find.byKey(const Key('partial-banner')), findsOneWidget);
      expect(find.byKey(const Key('quick-entry-cta')), findsOneWidget);
      expect(find.byKey(const Key('home-populated')), findsOneWidget);
    });
  }

  for (final moved in <HomeBlock>[
    HomeBlock.monthSummary,
    HomeBlock.trend,
    HomeBlock.recentTransactions,
    HomeBlock.primaryGoal,
  ]) {
    testWidgets('a failed ${moved.name} block no longer touches Home', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        repository: _ResultHomeRepository(
          HomePartialResult(
            snapshot: loadHomeFixtureSnapshotSync('populated.json'),
            blockFailures: {
              moved: const HomeBlockFailure(
                code: 'synthetic_unavailable',
                requestId: 'req_block_widget',
              ),
            },
          ),
        ),
      );
      await tester.pump();

      // The block moved to another screen, so its failure is that screen's
      // problem. Home keeps its own three and says nothing about it.
      expect(find.byKey(const Key('home-populated')), findsOneWidget);
      expect(find.byKey(const Key('balance-card')), findsOneWidget);
      expect(find.byKey(const Key('quick-entry-cta')), findsOneWidget);
      expect(find.byKey(const Key('upcoming-payments')), findsOneWidget);
    });
  }

  testWidgets('offline state keeps cached data and exposes its timestamp', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      repository: _ResultHomeRepository(
        HomeOfflineResult(loadHomeFixtureSnapshotSync('populated.json')),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('offline-banner')), findsOneWidget);
    expect(find.textContaining('UTC'), findsOneWidget);
    expect(find.byKey(const Key('balance-card')), findsOneWidget);
  });

  testWidgets('refresh retains data and reports a recoverable failure', (
    tester,
  ) async {
    final snapshot = loadHomeFixtureSnapshotSync('populated.json');
    final refresh = Completer<HomeRepositoryResult>();
    final repository = _SequenceHomeRepository([
      HomeDataResult(snapshot),
      refresh.future,
    ]);
    await _pumpApp(tester, repository: repository);
    await tester.pump();

    final context = tester.element(find.byKey(const Key('home-page')));
    final container = ProviderScope.containerOf(context, listen: false);
    final refreshFuture = container
        .read(homeControllerProvider.notifier)
        .refresh();
    await tester.pump();

    expect(find.byKey(const Key('refreshing-banner')), findsOneWidget);
    expect(find.byKey(const Key('balance-card')), findsOneWidget);

    refresh.complete(
      const HomeFailureResult(
        type: HomeFailureType.timeout,
        requestId: 'req_refresh_widget',
      ),
    );
    await refreshFuture;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('refresh-failure-banner')), findsOneWidget);
    expect(find.byKey(const Key('balance-card')), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('fatal failure retries and recovers', (tester) async {
    final repository = _SequenceHomeRepository([
      const HomeFailureResult(
        type: HomeFailureType.serviceUnavailable,
        requestId: 'req_fatal_widget',
      ),
      HomeDataResult(loadHomeFixtureSnapshotSync('populated.json')),
    ]);
    await _pumpApp(tester, repository: repository);
    await tester.pump();

    expect(find.byKey(const Key('home-fatal-error')), findsOneWidget);
    expect(find.textContaining('req_fatal_widget'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('home-populated')), findsOneWidget);
  });

  testWidgets('expired auth delegates one controlled sign-out request', (
    tester,
  ) async {
    final recovery = _TestSessionRecovery(
      HomeSessionRecoveryResult.signOutRequired,
    );
    var signOutRequests = 0;
    await _pumpHomePage(
      tester,
      repository: const _ResultHomeRepository(
        HomeAuthExpiredResult(requestId: 'req_auth_widget'),
      ),
      recovery: recovery,
      onSignOutRequested: () => signOutRequests += 1,
    );
    await tester.pump();

    expect(find.byKey(const Key('home-auth-required')), findsOneWidget);
    expect(recovery.calls, 1);

    await tester.tap(find.text('Войти снова'));
    await tester.pump();

    expect(signOutRequests, 1);
    expect(find.text('Повторный вход'), findsNothing);
  });

  testWidgets('mandatory error state fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpApp(
      tester,
      repository: const _ResultHomeRepository(
        HomeFailureResult(
          type: HomeFailureType.serviceUnavailable,
          requestId: 'req_accessibility_fixture',
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('home-fatal-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required HomeRepository repository,
  AppSettings settings = const AppSettings(),
  HomeSessionRecovery? recovery,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeRepositoryProvider.overrideWithValue(repository),
        homeSessionStoreProvider.overrideWithValue(
          const _NullHomeSessionStore(),
        ),
        initialAppSettingsProvider.overrideWithValue(settings),
        if (recovery != null)
          homeSessionRecoveryProvider.overrideWithValue(recovery),
      ],
      child: const FinanceApp(),
    ),
  );
  await tester.pump();
}

Future<void> _pumpHomePage(
  WidgetTester tester, {
  required HomeRepository repository,
  required HomeSessionRecovery recovery,
  required VoidCallback onSignOutRequested,
  VoidCallback? onManualEntryPressed,
  VoidCallback? onVoicePressed,
  VoidCallback onEntryPressed = _ignore,
  VoidCallback? onWaitingPhrasesPressed,
  List<WaitingPhrase> waiting = const [],
  bool listening = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (listening)
          voiceEntryControllerProvider.overrideWith(_ListeningController.new),
        waitingPhrasesProvider.overrideWith(() => _Waiting(waiting)),
        homeRepositoryProvider.overrideWithValue(repository),
        homeSessionRecoveryProvider.overrideWithValue(recovery),
        homeSessionStoreProvider.overrideWithValue(
          const _NullHomeSessionStore(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(AppAccent.teal),
        home: Scaffold(
          body: HomePage(
            localClock: _fixedLocalClock,
            onNotificationsPressed: _ignore,
            onEntryPressed: onEntryPressed,
            onVoicePressed: onVoicePressed,
            onWaitingPhrasesPressed: onWaitingPhrasesPressed,
            onAnalyticsPressed: _ignore,
            onGoalPressed: _ignore,
            onSignOutRequested: onSignOutRequested,
            onManualEntryPressed: onManualEntryPressed,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

DateTime _fixedLocalClock() => DateTime(2026, 7, 11, 8);

void _ignore() {}

class _ListeningController extends VoiceEntryController {
  @override
  bool build() => true;
}

class _Waiting extends WaitingPhrases {
  _Waiting(this._phrases);

  final List<WaitingPhrase> _phrases;

  @override
  List<WaitingPhrase> build() => _phrases;
}

class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;

  @override
  Future<void> clearSession() async {}
}

class _ValueHomeRepository implements HomeRepository {
  const _ValueHomeRepository(this.value);

  final HomeSnapshot? value;

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    if (value != null) return HomeDataResult(value!);
    return HomeFirstUseResult(
      HomeFirstUseData(
        userName: 'Максим',
        availableActions: {HomeAction.voiceEntry},
      ),
    );
  }
}

class _CompleterHomeRepository implements HomeRepository {
  final _completer = Completer<HomeRepositoryResult>();

  void complete(HomeRepositoryResult value) => _completer.complete(value);

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) =>
      _completer.future;
}

class _ResultHomeRepository implements HomeRepository {
  const _ResultHomeRepository(this.result);

  final HomeRepositoryResult result;

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async =>
      result;
}

class _SequenceHomeRepository implements HomeRepository {
  _SequenceHomeRepository(this.results);

  final List<Object> results;
  var calls = 0;

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    final result = results[calls++];
    if (result is Future<HomeRepositoryResult>) return result;
    return result as HomeRepositoryResult;
  }
}

class _TestSessionRecovery implements HomeSessionRecovery {
  _TestSessionRecovery(this.result);

  final HomeSessionRecoveryResult result;
  var calls = 0;

  @override
  Future<HomeSessionRecoveryResult> refreshSession() async {
    calls += 1;
    return result;
  }
}
