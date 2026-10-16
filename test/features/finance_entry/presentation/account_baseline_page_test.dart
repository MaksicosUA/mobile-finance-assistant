import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/features/auth/application/auth_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/account_baseline_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/account_baseline_page.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _accountCommandId = '33333333-3333-4333-8333-333333333333';
const _baselineCommandId = '44444444-4444-4444-8444-444444444444';
const _draftHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  testWidgets('completes localized review and confirmed correction', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    final context = tester.element(
      find.byKey(const Key('account-baseline-page')),
    );
    final materialL10n = MaterialLocalizations.of(context);
    final currentDate = materialL10n.formatMediumDate(DateTime(2026, 7, 10));
    final defaultDate = materialL10n.formatMediumDate(DateTime(2026, 7, 9));
    final correctedDate = materialL10n.formatMediumDate(DateTime(2026, 7));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(find.byKey(const Key('account-baseline-editing')), findsOneWidget);
    expect(find.text('Текущая дата начала учёта'), findsOneWidget);
    expect(find.text(currentDate), findsOneWidget);
    expect(find.text(defaultDate), findsOneWidget);
    expect(find.textContaining('2026-07-10'), findsNothing);
    expect(find.textContaining('100.00'), findsNothing);
    final dateAction = find.bySemanticsLabel('Новая дата: $defaultDate');
    expect(
      tester.getSemantics(dateAction),
      matchesSemantics(
        label: 'Новая дата: $defaultDate',
        textDirection: TextDirection.ltr,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    final container = ProviderScope.containerOf(context, listen: false);
    container
        .read(accountBaselineControllerProvider.notifier)
        .selectDate(DateTime.utc(2026, 7));
    await tester.pump();

    await tester.tap(find.byKey(const Key('account-baseline-evaluate')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-baseline-review')), findsOneWidget);
    expect(find.text(correctedDate), findsOneWidget);
    expect(find.textContaining('2026-07-01'), findsNothing);

    await tester.tap(find.byKey(const Key('account-baseline-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-baseline-accepted')), findsOneWidget);
    expect(find.text('Дата начала учёта изменена'), findsOneWidget);
    expect(repository.commits, hasLength(1));
    expect(repository.commits.single.draft.openingBalanceOn, '2026-07-01');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('editing is usable at 360 dp, dark mode and 200 percent text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpPage(
      tester,
      repository: _FakeRepository(),
      themeMode: ThemeMode.dark,
    );

    final context = tester.element(
      find.byKey(const Key('account-baseline-page')),
    );
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(
      tester.getSize(find.byKey(const Key('account-baseline-date'))).height,
      greaterThanOrEqualTo(48),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('account-baseline-evaluate')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('account-baseline-evaluate')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('load failure keeps request id and offers retry', (tester) async {
    final repository = _FakeRepository(
      listFailure: FinanceEntryFailure(
        kind: FinanceEntryFailureKind.serviceUnavailable,
        requestId: 'req_baseline_widget_failure',
      ),
    );
    await _pumpPage(tester, repository: repository);

    expect(find.byKey(const Key('account-baseline-failure')), findsOneWidget);
    expect(
      find.text('Код запроса: req_baseline_widget_failure'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('account-baseline-retry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account epoch reloads instead of leaving an endless spinner', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);
    final context = tester.element(
      find.byKey(const Key('account-baseline-page')),
    );
    final container = ProviderScope.containerOf(context, listen: false);
    expect(repository.listCalls, 1);

    container.read(authAccountEpochProvider.notifier).advance();
    await tester.pumpAndSettle();

    expect(repository.listCalls, 2);
    expect(find.byKey(const Key('account-baseline-editing')), findsOneWidget);
    expect(find.byKey(const Key('account-baseline-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeRepository repository,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeEntryRepositoryProvider.overrideWithValue(repository),
        financeCommandIdFactoryProvider.overrideWithValue(
          () => _baselineCommandId,
        ),
        financeEntryClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 8, 9, 12),
        ),
        homeRepositoryProvider.overrideWithValue(const _FirstUseHome()),
        homeSessionStoreProvider.overrideWithValue(
          const _NullHomeSessionStore(),
        ),
        acceptedWriteHomeDelayProvider.overrideWithValue((_) async {}),
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
        darkTheme: AppTheme.dark(AppAccent.teal),
        themeMode: themeMode,
        home: const AccountBaselinePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeRepository implements FinanceEntryRepositoryClient {
  @override
  Future<FinanceEntryResult<DateTime>> requestAccountDeletion({
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<void>> downloadAccountExport({
    required String savePath,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<void>> downloadOperationsTable({
    required String savePath,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<TransferProposal?>> parseTransferText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<FinanceTransferEvaluation>> evaluateTransfer(
    FinanceTransferDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceTransferCommitted>> commitTransfer(
    FinanceTransferCommitCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceTimezoneCorrected>> correctTimezone(
    FinanceTimezoneCommand command,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<BudgetsSnapshot>> readBudgets() =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<BudgetWritten>> setBudget(
    SetBudgetCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<BudgetWritten>> removeBudget(
    String budgetId,
    RemoveBudgetCommand command,
  ) => throw UnimplementedError();

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

  @override
  Future<FinanceEntryResult<OperationCorrected>> correctOperation(
    OperationCorrectionCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<OperationRemoved>> removeOperation(
    OperationRemovalCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceCategoryList>> listCategories() =>
      throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedCategoryList>> listManagedCategories() =>
      throw UnimplementedError();
  @override
  Future<FinanceEntryResult<AnalyticsSummary>> readAnalytics() =>
      throw UnimplementedError();
  @override
  Future<FinanceEntryResult<AnalyticsWindow>> readAnalyticsWindow({
    required AnalyticsPeriodKind period,
    String? from,
    String? to,
    String? accountId,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<UserProfile>> readProfile() =>
      throw UnimplementedError();
  @override
  Future<FinanceEntryResult<OperationProposal>> parseOperationText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<CategoryKeywords>> listCategoryKeywords(
    String categoryId,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<CategoryKeywords>> replaceCategoryKeywords(
    String categoryId,
    List<String> keywords,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required int limit,
    String? cursor,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> createCategory(
    CreateCategoryCommand command,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> renameCategory(
    String categoryId,
    RenameCategoryCommand command,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> archiveCategory(
    String categoryId,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> restoreCategory(
    String categoryId,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<SavingsGoalCreated>> createGoal(
    SavingsGoalDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<SavingsGoalList>> listGoals() =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<GoalContributionRecorded>> recordGoalContribution(
    String goalId,
    GoalContributionCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<SavingsGoalCancelled>> cancelGoal(
    String goalId,
    FinanceGoalCancelCommand command,
  ) => throw UnimplementedError();
  _FakeRepository({this.listFailure});

  final FinanceEntryFailure? listFailure;
  final List<FinanceBaselineCommitCommand> commits = [];
  int listCalls = 0;
  @override
  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost(
    PlannedCostDraft draft,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts() =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostSettled>> transitionPlannedCost(
    String plannedCostId,
    PlannedCostTransitionCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    listCalls += 1;
    final failure = listFailure;
    if (failure != null) {
      return FinanceEntryFailureResult<FinanceAccountSetup>(failure);
    }
    return _success(
      FinanceAccountSetup(
        canonicalTimezone: configuredHomeApiTimezone,
        timezoneRevision: 1,
        accounts: [_account('2026-07-10')],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline(
    FinanceBaselineDraft draft,
  ) async => _success<FinanceBaselineEvaluation>(
    FinanceBaselineNeedsConfirmation(
      draft: draft,
      currentOpeningBalanceOn: '2026-07-10',
      earliestOperationOn: null,
      draftHash: _draftHash,
    ),
  );

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline(
    FinanceBaselineCommitCommand command,
  ) async {
    commits.add(command);
    return _success(
      FinanceBaselineCommit(
        idempotentReplay: false,
        previousOpeningBalanceOn: '2026-07-10',
        account: _account(command.draft.openingBalanceOn),
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount(
    FinanceAccountDraft draft,
  ) => throw StateError('Unexpected account evaluation.');

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount(
    FinanceAccountCommitCommand command,
  ) => throw StateError('Unexpected account commit.');

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) => throw StateError('Unexpected operation evaluation.');

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation(
    FinanceOperationCommitCommand command, {
    required String expectedPrincipalScopeId,
    required String expectedSessionRevision,
    required FinanceCommitPreflight preflight,
  }) => throw StateError('Unexpected operation commit.');
}

FinanceEntrySuccess<T> _success<T>(T value) => FinanceEntrySuccess<T>(
  requestId: 'req_synthetic_account_baseline_widget',
  value: value,
);

FinanceAccount _account(String openingBalanceOn) => FinanceAccount(
  accountId: _accountId,
  userId: _userId,
  commandId: _accountCommandId,
  name: 'Тестовый счёт',
  currency: 'EUR',
  openingBalance: '100.00',
  openingBalanceOn: openingBalanceOn,
  openingTimezone: configuredHomeApiTimezone,
  isDefault: true,
  confirmedAt: '2026-07-10T08:00:00.000Z',
  createdAt: '2026-07-10T08:00:01.000Z',
);

final class _FirstUseHome implements HomeRepository, HomeCacheInvalidator {
  const _FirstUseHome();

  @override
  Future<void> invalidateHomeCache() async {}

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    return HomeFirstUseResult(
      HomeFirstUseData(userName: 'Тест', availableActions: const {}),
    );
  }
}

final class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<void> clearSession() async {}

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;
}
