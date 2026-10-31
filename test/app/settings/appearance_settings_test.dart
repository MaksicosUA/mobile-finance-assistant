import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/language/app_language.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/settings/settings_widgets.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

/// The appearance controls used to live on their own Settings screen, reached
/// by a gear on Home. They are part of Profile now (ADR 0021), so their
/// behaviour is tested here rather than through Home.
void main() {
  testWidgets('every accent choice repaints the app natively', (tester) async {
    await _pumpSection(tester);

    for (final accent in AppAccent.values) {
      await tester.tap(find.byKey(Key('accent-${accent.name}')));
      await tester.pump();
      final context = tester.element(find.byKey(const Key('appearance-host')));
      expect(Theme.of(context).colorScheme.primary, accent.color);
    }
  });

  testWidgets('choosing the dark theme switches brightness', (tester) async {
    await _pumpSection(tester);

    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pump();

    final context = tester.element(find.byKey(const Key('appearance-host')));
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  testWidgets('the app says which language it is following', (tester) async {
    await _pumpSection(tester);

    expect(find.text('Как на телефоне'), findsOneWidget);
    // Always written in itself, in case the screen is in a language the person
    // cannot read.
    await tester.ensureVisible(find.byKey(const Key('settings-language')));
    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();

    expect(find.text('Українська'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);
  });

  testWidgets('choosing a language keeps it', (tester) async {
    await _pumpSection(tester);

    await tester.ensureVisible(find.byKey(const Key('settings-language')));
    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-de')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byKey(const Key('appearance-host')));
    final container = ProviderScope.containerOf(context);
    expect(
      container.read(appSettingsControllerProvider).language,
      AppLanguage.german,
    );
    expect(find.text('Deutsch'), findsOneWidget);
  });

  testWidgets('closing the sheet is not a choice', (tester) async {
    await _pumpSection(tester);

    await tester.ensureVisible(find.byKey(const Key('settings-language')));
    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final context = tester.element(find.byKey(const Key('appearance-host')));
    final container = ProviderScope.containerOf(context);
    expect(container.read(appSettingsControllerProvider).language, isNull);
  });

  testWidgets('following the phone can be chosen again', (tester) async {
    await _pumpSection(tester);
    final context = tester.element(find.byKey(const Key('appearance-host')));
    final container = ProviderScope.containerOf(context);
    container
        .read(appSettingsControllerProvider.notifier)
        .setLanguage(AppLanguage.german);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('settings-language')));
    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-phone')));
    await tester.pumpAndSettle();

    expect(container.read(appSettingsControllerProvider).language, isNull);
  });

  testWidgets('privacy is a switch, not a hidden preference', (tester) async {
    await _pumpSection(tester);

    await tester.tap(find.byKey(const Key('settings-privacy-toggle')));
    await tester.pump();

    final toggle = tester.widget<Switch>(
      find.byKey(const Key('settings-privacy-toggle')),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('the theme cards stack instead of overflowing at 200 percent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpSection(tester, textScale: 2);

    expect(find.byKey(const Key('theme-light')), findsOneWidget);
    expect(find.byKey(const Key('theme-dark')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSection(WidgetTester tester, {double textScale = 1}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(appSettingsControllerProvider);
          return MaterialApp(
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
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: textScale,
              maxScaleFactor: textScale,
              child: child!,
            ),
            home: const Scaffold(
              key: Key('appearance-host'),
              body: SingleChildScrollView(child: AppearanceSettingsSection()),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
