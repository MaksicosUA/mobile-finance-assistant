import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/features/home/presentation/widgets/spending_chart.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

/// The chart itself.
///
/// It rendered nothing on a device for as long as it existed: the canvas was
/// given a height and no width, so the painter returned on an empty size. No
/// test asserted anything was drawn, which is why the whole suite stayed
/// green.
void main() {
  testWidgets('the canvas is given a width, so the line is actually painted', (
    tester,
  ) async {
    await _pump(tester, _trend());

    final canvas = find.byKey(const Key('spending-chart-canvas'));
    expect(tester.getSize(canvas).width, greaterThan(0));
    // The painter draws the filled area and then the line above it.
    expect(
      tester.renderObject(canvas),
      paints
        ..path()
        ..path(),
    );
  });

  testWidgets('a flat series is still a line, not a blank card', (
    tester,
  ) async {
    await _pump(
      tester,
      _trend(amounts: const ['30000.00', '30000.00', '30000.00']),
    );

    expect(
      tester.renderObject(find.byKey(const Key('spending-chart-canvas'))),
      paints
        ..path()
        ..path(),
    );
  });

  testWidgets('without a header figure the card shows only its title', (
    tester,
  ) async {
    await _pump(tester, _trend());

    // The window's result moved under the chart, where the screen reports it.
    expect(find.text('за период +2 200,00 €'), findsNothing);
    expect(find.text('Баланс'), findsOneWidget);
  });

  testWidgets('privacy mode paints no line at all', (tester) async {
    await _pump(tester, _trend(), privacy: true);

    expect(find.byKey(const Key('spending-chart-canvas')), findsNothing);
    expect(find.text('суммы скрыты'), findsOneWidget);
  });
}

TrendSummary _trend({List<String>? amounts}) {
  final values = amounts ?? const ['30000.00', '31000.00', '32200.00'];
  return TrendSummary(
    metric: TrendMetric.balance,
    period: TrendPeriod.days7,
    total: Money(amount: values.last, currency: 'EUR'),
    points: [
      for (var index = 0; index < values.length; index++)
        TrendPoint(
          date: DateTime.utc(2026, 8, index + 1),
          amount: Money(amount: values[index], currency: 'EUR'),
        ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  TrendSummary trend, {
  bool privacy = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
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
        body: SpendingChart(
          trend: trend,
          title: 'Баланс',
          periodDescription: '30 000,00 € → 32 200,00 €',
          periodLabel: null,
          detailsLabel: 'Подробнее',
          emptyLabel: 'Нет данных',
          semanticsLabel: 'Баланс, 32 200,00 €',
          amountsHiddenLabel: 'суммы скрыты',
          privacyEnabled: privacy,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
