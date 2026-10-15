import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/home/presentation/widgets/balance_card.dart';

/// The arrow beside the month's result says which way it went.
///
/// It was a constant «↗», so a month that lost money showed an arrow pointing
/// up beside a minus — the arrow and the number disagreeing on one line.
void main() {
  testWidgets('a month that lost money points down', (tester) async {
    await _pump(tester, delta: '−100,00 €', trend: BalanceTrend.down);

    expect(find.textContaining('↘'), findsOneWidget);
    expect(find.textContaining('↗'), findsNothing);
  });

  testWidgets('a month that gained points up', (tester) async {
    await _pump(tester, delta: '+240,00 €', trend: BalanceTrend.up);

    expect(find.textContaining('↗'), findsOneWidget);
    expect(find.textContaining('↘'), findsNothing);
  });

  testWidgets('a month that came out even points nowhere in particular', (
    tester,
  ) async {
    await _pump(tester, delta: '0,00 €', trend: BalanceTrend.flat);

    expect(find.textContaining('→'), findsOneWidget);
    expect(find.textContaining('↗'), findsNothing);
    expect(find.textContaining('↘'), findsNothing);
  });

  testWidgets('privacy hides the direction along with the amount', (
    tester,
  ) async {
    // The way a month went is itself something about the money: an arrow
    // beside a masked amount would still tell an onlooker which way it went.
    await _pump(tester, delta: '•••••• €', trend: null);

    expect(find.textContaining('↗'), findsNothing);
    expect(find.textContaining('↘'), findsNothing);
    expect(find.textContaining('→'), findsNothing);
    expect(find.textContaining('•••••• €'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required String delta,
  required BalanceTrend? trend,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(AppAccent.teal),
      home: Scaffold(
        body: BalanceCard(
          title: 'Баланс',
          balance: '150 951,76 €',
          delta: delta,
          deltaTrend: trend,
          deltaPercent: null,
          monthDeltaLabel: 'за месяц',
          deltaUnavailableLabel: 'нет данных',
          accountsLabel: 'Основной',
          privacyLabel: 'Скрыть суммы',
          privacyEnabled: trend == null,
          onTogglePrivacy: () {},
        ),
      ),
    ),
  );
}
