import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/app_shell.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/features/home/presentation/home_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

import '../../../support/home_contract_fixture.dart';

void main() {
  group('stable Home goldens', () {
    testWidgets('initial loading light at 360 dp', (tester) async {
      await _pumpGolden(
        tester,
        size: const Size(360, 800),
        snapshot: null,
        loading: true,
      );

      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/home_loading_light_360.png'),
      );
    });

    testWidgets('populated light at 360 dp', (tester) async {
      await _pumpGolden(
        tester,
        size: const Size(360, 800),
        snapshot: loadHomeFixtureSnapshotSync('populated.json'),
      );

      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/home_populated_light_360.png'),
      );
    });

    testWidgets('populated dark at 390 dp', (tester) async {
      await _pumpGolden(
        tester,
        size: const Size(390, 844),
        snapshot: loadHomeFixtureSnapshotSync('populated.json'),
        settings: const AppSettings(
          themeMode: ThemeMode.dark,
          accent: AppAccent.blue,
        ),
      );

      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/home_populated_dark_390.png'),
      );
    });

    testWidgets('first-use empty light at 430 dp', (tester) async {
      await _pumpGolden(tester, size: const Size(430, 844), snapshot: null);

      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/home_empty_light_430.png'),
      );
    });

    testWidgets('privacy dark at 360 dp', (tester) async {
      await _pumpGolden(
        tester,
        size: const Size(360, 800),
        snapshot: loadHomeFixtureSnapshotSync('populated.json'),
        settings: const AppSettings(
          themeMode: ThemeMode.dark,
          accent: AppAccent.terracotta,
          privacyMode: true,
        ),
      );

      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/home_privacy_dark_360.png'),
      );
    });

    testWidgets('privacy light at 360 dp', (tester) async {
      await _pumpGolden(
        tester,
        size: const Size(360, 800),
        snapshot: loadHomeFixtureSnapshotSync('populated.json'),
        settings: const AppSettings(privacyMode: true),
      );

      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/home_privacy_light_360.png'),
      );
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      final suffix = brightness.name;
      final settings = AppSettings(
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
      );

      testWidgets('partial $suffix at 390 dp', (tester) async {
        final snapshot = loadHomeFixtureSnapshotSync('populated.json');
        await _pumpGolden(
          tester,
          size: const Size(390, 844),
          snapshot: snapshot,
          result: HomePartialResult(
            snapshot: snapshot,
            blockFailures: const {
              HomeBlock.primaryGoal: HomeBlockFailure(
                code: 'goal_unavailable',
                requestId: 'req_golden_goal',
              ),
            },
          ),
          settings: settings,
        );

        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile('goldens/home_partial_${suffix}_390.png'),
        );
      });

      testWidgets('offline $suffix at 390 dp', (tester) async {
        final snapshot = loadHomeFixtureSnapshotSync('populated.json');
        await _pumpGolden(
          tester,
          size: const Size(390, 844),
          snapshot: snapshot,
          result: HomeOfflineResult(snapshot),
          settings: settings,
        );

        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile('goldens/home_offline_${suffix}_390.png'),
        );
      });

      testWidgets('fatal $suffix at 390 dp', (tester) async {
        await _pumpGolden(
          tester,
          size: const Size(390, 844),
          snapshot: null,
          result: const HomeFailureResult(
            type: HomeFailureType.serviceUnavailable,
            requestId: 'req_golden_fatal',
          ),
          settings: settings,
        );

        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile('goldens/home_fatal_${suffix}_390.png'),
        );
      });
    }

    testWidgets('populated secondary blocks light at 430 dp', (tester) async {
      await _pumpGolden(
        tester,
        size: const Size(430, 844),
        snapshot: loadHomeFixtureSnapshotSync('populated.json'),
      );
      await tester.drag(
        find.byKey(const Key('home-page')),
        const Offset(0, -920),
      );
      await tester.pump();

      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/home_secondary_blocks_light_430.png'),
      );
    });

    testWidgets('nullable and empty blocks dark at 430 dp', (tester) async {
      await _pumpGolden(
        tester,
        size: const Size(430, 844),
        snapshot: loadHomeFixtureSnapshotSync('empty_lists.json'),
        settings: const AppSettings(
          themeMode: ThemeMode.dark,
          accent: AppAccent.purple,
        ),
      );
      await tester.drag(
        find.byKey(const Key('home-page')),
        const Offset(0, -720),
      );
      await tester.pump();

      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/home_empty_blocks_dark_430.png'),
      );
    });
  });
}

Future<void> _pumpGolden(
  WidgetTester tester, {
  required Size size,
  required HomeSnapshot? snapshot,
  AppSettings settings = const AppSettings(),
  bool loading = false,
  HomeRepositoryResult? result,
}) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeRepositoryProvider.overrideWithValue(
          loading
              ? const _PendingGoldenRepository()
              : _ResultGoldenRepository(
                  result ??
                      (snapshot == null
                          ? HomeFirstUseResult(
                              HomeFirstUseData(
                                userName: 'Максим',
                                availableActions: {HomeAction.voiceEntry},
                              ),
                            )
                          : HomeDataResult(snapshot)),
                ),
        ),
        initialAppSettingsProvider.overrideWithValue(settings),
      ],
      child: const _GoldenFinanceApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  expect(tester.takeException(), isNull);
}

class _GoldenFinanceApp extends ConsumerWidget {
  const _GoldenFinanceApp();

  static final DateTime _localNow = DateTime(2026, 7, 11, 8, 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(settings.accent),
      darkTheme: AppTheme.dark(settings.accent),
      themeMode: settings.themeMode,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: HomePage(
          localClock: () => _localNow,
          onOpenSettings: _ignore,
          onNotificationsPressed: _ignore,
          onVoicePressed: _ignore,
          onAnalyticsPressed: _ignore,
          onGoalPressed: _ignore,
          onSignOutRequested: _ignore,
        ),
        bottomNavigationBar: const AppBottomNavigation(
          selected: AppSection.home,
          onSelected: _ignoreSection,
        ),
      ),
    );
  }

  static void _ignore() {}

  static void _ignoreSection(AppSection _) {}
}

class _ResultGoldenRepository implements HomeRepository {
  const _ResultGoldenRepository(this.result);

  final HomeRepositoryResult result;

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async =>
      result;
}

class _PendingGoldenRepository implements HomeRepository {
  const _PendingGoldenRepository();

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) =>
      Completer<HomeRepositoryResult>().future;
}
