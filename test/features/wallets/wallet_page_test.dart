import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/wallets/domain/currency_options.dart';
import 'package:mobile_finance_assistant/features/wallets/presentation/wallet_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  test('every offered currency is one the server would accept', () {
    final codes = currencyOptions.map((option) => option.code).toList();

    expect(codes.toSet().length, codes.length);
    for (final code in codes) {
      expect(RegExp(r'^[A-Z]{3}$').hasMatch(code), isTrue, reason: code);
    }
  });

  testWidgets('a currency is searched by name or by code', (tester) async {
    await _pump(tester, repository: _FakeRepository());

    await tester.tap(find.byKey(const Key('wallet-currency')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('wallet-currency-search')),
      'лек',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet-currency-ALL')), findsOneWidget);
    expect(find.byKey(const Key('wallet-currency-EUR')), findsNothing);
  });

  testWidgets('a currency already held is marked and still offered', (
    tester,
  ) async {
    // A bank account and cash are both euro and both real (ADR 0029).
    await _pump(tester, repository: _FakeRepository());

    await tester.tap(find.byKey(const Key('wallet-currency')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('wallet-currency-search')),
      'EUR',
    );
    await tester.pumpAndSettle();

    expect(find.text('Уже есть'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wallet-currency-EUR')));
    await tester.pumpAndSettle();
    expect(find.text('EUR'), findsWidgets);
  });

  testWidgets('a reviewed wallet is opened and reported', (tester) async {
    final repository = _FakeRepository();
    await _pump(tester, repository: repository);

    await _fill(tester);
    await tester.tap(find.byKey(const Key('wallet-review')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wallet-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet-opened')), findsOneWidget);
    expect(repository.opened, hasLength(1));
    // The profile's own zone, never a second one (ADR 0028).
    expect(repository.evaluated.single.canonicalTimezone, 'Europe/Berlin');
    expect(repository.evaluated.single.currency, 'UAH');
  });

  testWidgets('editing takes the confirmation away', (tester) async {
    await _pump(tester, repository: _FakeRepository());

    await _fill(tester);
    await tester.tap(find.byKey(const Key('wallet-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wallet-confirm')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('wallet-name')), 'Другое имя');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet-confirm')), findsNothing);
  });

  testWidgets('a wallet needs the first account to exist', (tester) async {
    await _pump(tester, repository: _FakeRepository(hasAccount: false));

    expect(find.byKey(const Key('wallet-account-required')), findsOneWidget);
    expect(find.byKey(const Key('wallet-form')), findsNothing);
  });
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('wallet-name')), 'Гривна');
  await tester.tap(find.byKey(const Key('wallet-currency')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('wallet-currency-search')),
    'UAH',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('wallet-currency-UAH')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('wallet-opening-balance')),
    '1200',
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRepository repository,
}) async {
  final container = ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      financeEntryClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 9, 8, 12),
      ),
      financeCommandIdFactoryProvider.overrideWithValue(
        () => '33333333-3333-4333-8333-333333333333',
      ),
      initialAppSettingsProvider.overrideWithValue(const AppSettings()),
      homeRepositoryProvider.overrideWithValue(const _SilentHomeRepository()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(AppAccent.teal),
        home: const WalletPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _SilentHomeRepository implements HomeRepository {
  const _SilentHomeRepository();

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    return const HomeFailureResult(
      type: HomeFailureType.unknown,
      requestId: 'req_synthetic_home',
    );
  }
}

final class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository({this.hasAccount = true});

  final bool hasAccount;
  final List<FinanceAccountDraft> evaluated = [];
  final List<FinanceAccountCommitCommand> opened = [];

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    return FinanceEntrySuccess<FinanceAccountSetup>(
      requestId: 'req_synthetic_wallet',
      value: FinanceAccountSetup(
        canonicalTimezone: hasAccount ? 'Europe/Berlin' : null,
        timezoneRevision: hasAccount ? 1 : 0,
        accounts: [
          if (hasAccount)
            FinanceAccount(
              accountId: '11111111-1111-4111-8111-111111111111',
              userId: '77777777-7777-4777-8777-777777777777',
              commandId: '88888888-8888-4888-8888-888888888888',
              name: 'Основной',
              currency: 'EUR',
              openingBalance: '1000.00',
              openingBalanceOn: '2026-01-01',
              openingTimezone: 'Europe/Berlin',
              isDefault: true,
              confirmedAt: '2026-01-01T10:00:00.000Z',
              createdAt: '2026-01-01T10:00:00.000Z',
            ),
        ],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount(
    FinanceAccountDraft draft,
  ) async {
    evaluated.add(draft);
    return FinanceEntrySuccess<FinanceAccountEvaluation>(
      requestId: 'req_synthetic_wallet',
      value: FinanceAccountNeedsConfirmation(draft: draft, draftHash: _hash),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount(
    FinanceAccountCommitCommand command,
  ) async {
    opened.add(command);
    return FinanceEntrySuccess<FinanceAccountCommit>(
      requestId: 'req_synthetic_wallet',
      value: FinanceAccountCommit(
        idempotentReplay: false,
        canonicalTimezone: 'Europe/Berlin',
        timezoneRevision: 1,
        account: FinanceAccount(
          accountId: '22222222-2222-4222-8222-222222222222',
          userId: '77777777-7777-4777-8777-777777777777',
          commandId: command.review.draft.commandId,
          name: command.review.draft.name,
          currency: command.review.draft.currency,
          openingBalance: command.review.draft.openingBalance,
          openingBalanceOn: command.review.draft.openingBalanceOn,
          openingTimezone: command.review.draft.canonicalTimezone,
          isDefault: false,
          confirmedAt: '2026-09-08T12:00:00.000Z',
          createdAt: '2026-09-08T12:00:00.000Z',
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
