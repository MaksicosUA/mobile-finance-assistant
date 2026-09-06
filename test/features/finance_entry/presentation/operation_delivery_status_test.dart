import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/finance_entry_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _sensitiveAmount = '987654.32';
const _sensitiveMerchant = 'Sensitive merchant';

void main() {
  _deliveryStateTest(
    name: 'queued',
    cardKey: const Key('operation-queued'),
    state: FinanceOperationQueued(
      account: _account(),
      latestOperationDate: DateTime(2026, 7, 29),
      authenticationRequired: false,
    ),
  );
  _deliveryStateTest(
    name: 'already synced',
    cardKey: const Key('operation-already-synced'),
    state: FinanceOperationAlreadySynced(
      account: _account(),
      latestOperationDate: DateTime(2026, 7, 29),
    ),
  );
  _deliveryStateTest(
    name: 'attention',
    cardKey: const Key('operation-delivery-attention'),
    state: FinanceOperationDeliveryAttention(
      account: _account(),
      latestOperationDate: DateTime(2026, 7, 29),
      issue: FinanceOperationDeliveryIssue.commandConflict,
    ),
  );
}

void _deliveryStateTest({
  required String name,
  required Key cardKey,
  required FinanceEntryState state,
}) {
  testWidgets(
    '$name status is safe at 360 dp, dark theme, and 200 percent text scale',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpPage(tester, state);

      expect(find.byKey(cardKey), findsOneWidget);
      final pageContext = tester.element(
        find.byKey(const Key('finance-entry-page')),
      );
      expect(Theme.of(pageContext).brightness, Brightness.dark);
      expect(find.textContaining(_sensitiveAmount), findsNothing);
      expect(find.textContaining(_sensitiveMerchant), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(_sensitiveAmount))),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(_sensitiveMerchant))),
        findsNothing,
      );
      expect(
        find.semantics.byValue(RegExp(RegExp.escape(_sensitiveAmount))),
        findsNothing,
      );
      expect(
        find.semantics.byValue(RegExp(RegExp.escape(_sensitiveMerchant))),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}

Future<void> _pumpPage(WidgetTester tester, FinanceEntryState state) async {
  const settings = AppSettings(
    themeMode: ThemeMode.dark,
    accent: AppAccent.purple,
    privacyMode: true,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(settings),
        financeEntryControllerProvider.overrideWith(
          () => _FixedFinanceEntryController(state),
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
        theme: AppTheme.light(settings.accent),
        darkTheme: AppTheme.dark(settings.accent),
        themeMode: settings.themeMode,
        home: const Scaffold(
          body: FinanceEntryPage(
            onBackHome: _ignore,
            onSignInRequested: _ignore,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FinanceAccount _account() => const FinanceAccount(
  accountId: '11111111-1111-4111-8111-111111111111',
  userId: '22222222-2222-4222-8222-222222222222',
  commandId: '33333333-3333-4333-8333-333333333333',
  name: _sensitiveMerchant,
  currency: 'EUR',
  openingBalance: _sensitiveAmount,
  openingBalanceOn: '2026-07-01',
  openingTimezone: 'Europe/Berlin',
  isDefault: true,
  confirmedAt: '2026-07-01T08:00:00Z',
  createdAt: '2026-07-01T08:00:00Z',
);

final class _FixedFinanceEntryController extends FinanceEntryController {
  _FixedFinanceEntryController(this.initialState);

  final FinanceEntryState initialState;

  @override
  FinanceEntryState build() => initialState;

  @override
  Future<void> load() async {}
}

void _ignore() {}
