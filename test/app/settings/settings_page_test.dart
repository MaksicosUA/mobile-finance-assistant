import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/settings/settings_page.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'authenticated settings expose an accessible opening-date action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var requests = 0;
      await _pumpSettings(tester, onCorrectOpeningDate: () => requests += 1);

      expect(find.byKey(const Key('settings-opening-date')), findsOneWidget);
      expect(find.text('Дата начала учёта'), findsOneWidget);
      final action = find.bySemanticsLabel(
        'Дата начала учёта. Разрешить операции за более ранний период',
      );
      expect(
        tester.getSemantics(action),
        matchesSemantics(
          label: 'Дата начала учёта. Разрешить операции за более ранний период',
          textDirection: TextDirection.ltr,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.byKey(const Key('settings-opening-date')));

      expect(requests, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('opening-date action fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpSettings(tester, onCorrectOpeningDate: () {});
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-opening-date')),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const Key('settings-opening-date')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fixture settings do not expose server account actions', (
    tester,
  ) async {
    await _pumpSettings(tester);

    expect(find.byKey(const Key('settings-opening-date')), findsNothing);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  VoidCallback? onCorrectOpeningDate,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
        home: SettingsPage(onCorrectOpeningDate: onCorrectOpeningDate),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
