import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/app_shell.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/operation_sync_controller.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'Home convergence banner is safe at 360 dp, dark, and 200 percent text scale',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var retryCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: AppTheme.light(AppAccent.purple),
          darkTheme: AppTheme.dark(AppAccent.purple),
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OperationSyncStatusBanner(
                  state: const OperationSyncState(
                    phase: OperationSyncPhase.homeConvergencePending,
                    homeConvergenceCount: 1,
                  ),
                  onRetry: () => retryCalls += 1,
                  onSignIn: () => fail('Sign-in must not be requested.'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const bannerKey = Key('operation-home-convergence-banner');
      expect(find.byKey(bannerKey), findsOneWidget);
      expect(find.text('Главный экран обновляется'), findsOneWidget);
      expect(
        find.textContaining('Операция уже сохранена сервером'),
        findsOneWidget,
      );
      expect(
        find.textContaining(RegExp('ждёт синхронизации', caseSensitive: false)),
        findsNothing,
      );

      final bannerContext = tester.element(find.byKey(bannerKey));
      expect(Theme.of(bannerContext).brightness, Brightness.dark);

      final bannerSemantics = tester.getSemantics(find.byKey(bannerKey));
      expect(bannerSemantics.label, contains('Главный экран обновляется'));
      expect(
        bannerSemantics.label,
        contains('Операция уже сохранена сервером'),
      );
      expect(
        bannerSemantics.label,
        isNot(matches(RegExp(r'\d|[€$₽]|руб(?:ль|ля|лей)?'))),
      );
      expect(
        find.bySemanticsLabel(
          RegExp('ждёт синхронизации', caseSensitive: false),
        ),
        findsNothing,
      );

      final retryButton = find.widgetWithText(TextButton, 'Обновить сейчас');
      expect(retryButton, findsOneWidget);
      final retrySemantics = tester.getSemantics(retryButton);
      expect(
        retrySemantics.label,
        isNot(matches(RegExp(r'\d|[€$₽]|руб(?:ль|ля|лей)?'))),
      );
      await tester.tap(retryButton);
      await tester.pump();

      expect(retryCalls, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
