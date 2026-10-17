import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/planned_cost_page.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _hryvniaAccountId = '77777777-7777-4777-8777-777777777777';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _accountCommandId = '33333333-3333-4333-8333-333333333333';
const _planCommandId = '44444444-4444-4444-8444-444444444444';
const _planId = '55555555-5555-4555-8555-555555555555';
const _recurrenceId = '66666666-6666-4666-8666-666666666666';

void main() {
  testWidgets('editing form fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpPage(tester, repository: _FakeRepository(), textScale: 2);

    expect(find.byKey(const Key('planned-cost-editing')), findsOneWidget);
    expect(find.byKey(const Key('planned-cost-title')), findsOneWidget);

    // At 200% the form is taller than the viewport, so what matters is that
    // every control stays reachable by scrolling and nothing overflows.
    await tester.scrollUntilVisible(
      find.byKey(const Key('planned-cost-submit')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('planned-cost-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a user without an account is told to create one', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository(hasAccount: false));

    expect(find.byKey(const Key('planned-cost-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('planned-cost-editing')), findsNothing);
  });

  testWidgets('a load failure offers a retry', (tester) async {
    final repository = _FakeRepository(
      listFailure: FinanceEntryFailure(
        kind: FinanceEntryFailureKind.serviceUnavailable,
        requestId: 'req_synthetic_planned_cost',
      ),
    );

    await _pumpPage(tester, repository: repository);

    expect(find.byKey(const Key('planned-cost-failure')), findsOneWidget);
    expect(repository.listCalls, 1);
  });

  testWidgets('a refused plan explains the baseline bound', (tester) async {
    final repository = _FakeRepository(
      createResult: FinanceEntryFailureResult<PlannedCostCreated>(
        FinanceEntryFailure(
          kind: FinanceEntryFailureKind.rejected,
          requestId: 'req_synthetic_planned_cost',
          code: FinanceEntryErrorCode.plannedCostRejected,
          plannedCostIssues: const [
            PlannedCostIssue(
              code: PlannedCostIssueCode.planBeforeAccountBaseline,
              field: 'plannedOn',
            ),
          ],
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('planned-cost-title')),
      'Аренда',
    );
    await tester.enterText(
      find.byKey(const Key('planned-cost-amount')),
      '800.00',
    );
    await tester.tap(find.byKey(const Key('planned-cost-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('planned-cost-message')), findsOneWidget);
    // The refusal names the actual cause instead of a bare error.
    expect(find.textContaining('начала учёта'), findsOneWidget);
  });

  testWidgets('an accepted plan says it does not change the balance', (
    tester,
  ) async {
    final repository = _FakeRepository(
      createResult: FinanceEntrySuccess<PlannedCostCreated>(
        requestId: 'req_synthetic_planned_cost',
        value: const PlannedCostCreated(
          plannedCost: PlannedCost(
            plannedCostId: _planId,
            accountId: _accountId,
            amount: '800.00',
            currency: 'EUR',
            title: 'Аренда',
            plannedOn: '2026-09-01',
            status: 'planned',
            isDue: false,
          ),
          idempotentReplay: false,
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('planned-cost-title')),
      'Аренда',
    );
    await tester.enterText(
      find.byKey(const Key('planned-cost-amount')),
      '800.00',
    );
    await tester.tap(find.byKey(const Key('planned-cost-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('planned-cost-accepted')), findsOneWidget);
    expect(find.textContaining('не влияет на баланс'), findsOneWidget);
    expect(find.byKey(const Key('planned-cost-home-status')), findsOneWidget);
  });

  testWidgets('outstanding plans are listed and can be cancelled', (
    tester,
  ) async {
    final repository = _FakeRepository(
      plans: const [
        PlannedCost(
          plannedCostId: _planId,
          accountId: _accountId,
          amount: '800.00',
          currency: 'EUR',
          title: 'Аренда',
          plannedOn: '2026-09-01',
          status: 'planned',
          isDue: false,
        ),
      ],
      settleResult: FinanceEntrySuccess<PlannedCostSettled>(
        requestId: 'req_synthetic_planned_cost',
        value: const PlannedCostSettled(
          plannedCost: PlannedCost(
            plannedCostId: _planId,
            accountId: _accountId,
            amount: '800.00',
            currency: 'EUR',
            title: 'Аренда',
            plannedOn: '2026-09-01',
            status: 'cancelled',
            isDue: false,
          ),
          idempotentReplay: false,
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    final row = find.byKey(const Key('planned-cost-plan-$_planId'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(row, findsOneWidget);

    final cancel = find.byKey(const Key('planned-cost-cancel-$_planId'));
    await tester.scrollUntilVisible(
      cancel,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel, warnIfMissed: true);
    await tester.pumpAndSettle();

    expect(repository.settled, [_planId]);
    expect(find.byKey(const Key('planned-cost-list-empty')), findsOneWidget);
  });

  testWidgets('an empty plan list says so instead of showing nothing', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository());

    await tester.scrollUntilVisible(
      find.byKey(const Key('planned-cost-list-empty')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('planned-cost-list-empty')), findsOneWidget);
  });

  // --- repeating plans (ADR 0025) --------------------------------------------

  testWidgets('the repeat switch turns the form into a series', (tester) async {
    final repository = _FakeRepository(
      createRecurrenceResult: FinanceEntrySuccess<PlannedCostRecurrenceCreated>(
        requestId: 'req_synthetic_recurrence',
        value: PlannedCostRecurrenceCreated(
          recurrence: _recurrence(),
          idempotentReplay: false,
          occurrences: const ['2026-08-31', '2026-09-30', '2026-10-31'],
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('planned-cost-title')),
      'Аренда',
    );
    await tester.enterText(
      find.byKey(const Key('planned-cost-amount')),
      '800.00',
    );
    await _tapAt(tester, const Key('planned-cost-repeat'));
    await _tapAt(tester, const Key('planned-cost-last-day'));
    await _tapAt(tester, const Key('planned-cost-submit'));

    expect(repository.drafts, isEmpty);
    expect(repository.recurrenceDrafts, hasLength(1));
    // «The last day of the month» is stored as 31: under clamping the two are
    // the same schedule, so there is no second concept in the wire format.
    expect(repository.recurrenceDrafts.single.dayOfMonth, 31);
    expect(repository.recurrenceDrafts.single.toJson()['frequency'], 'monthly');
  });

  testWidgets('an accepted series shows where the anchor lands', (
    tester,
  ) async {
    final repository = _FakeRepository(
      createRecurrenceResult: FinanceEntrySuccess<PlannedCostRecurrenceCreated>(
        requestId: 'req_synthetic_recurrence',
        value: PlannedCostRecurrenceCreated(
          recurrence: _recurrence(),
          idempotentReplay: false,
          occurrences: const ['2026-01-31', '2026-02-28', '2026-03-31'],
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('planned-cost-title')),
      'Аренда',
    );
    await tester.enterText(
      find.byKey(const Key('planned-cost-amount')),
      '800.00',
    );
    await _tapAt(tester, const Key('planned-cost-repeat'));
    await _tapAt(tester, const Key('planned-cost-submit'));

    expect(
      find.byKey(const Key('planned-cost-recurrence-accepted')),
      findsOneWidget,
    );
    // February is on screen before February happens. That is the point of
    // reporting the dates at all.
    expect(
      find.byKey(const Key('recurrence-occurrence-2026-02-28')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a short-month warning appears only for an anchor past the 28th',
    (tester) async {
      await _pumpPage(tester, repository: _FakeRepository());

      await _tapAt(tester, const Key('planned-cost-repeat'));
      // The clock is 9 August, so the anchor is the 9th: nothing to warn about.
      expect(
        find.byKey(const Key('planned-cost-short-month-hint')),
        findsNothing,
      );

      await _tapAt(tester, const Key('planned-cost-last-day'));
      await tester.ensureVisible(
        find.byKey(const Key('planned-cost-short-month-hint')),
      );
      expect(
        find.byKey(const Key('planned-cost-short-month-hint')),
        findsOneWidget,
      );
    },
  );

  testWidgets('skipping is offered on a series instance and not on a one-off', (
    tester,
  ) async {
    const otherPlanId = '77777777-7777-4777-8777-777777777777';
    final repository = _FakeRepository(
      plans: const [
        PlannedCost(
          plannedCostId: _planId,
          accountId: _accountId,
          amount: '800.00',
          currency: 'EUR',
          title: 'Аренда',
          plannedOn: '2026-09-30',
          status: 'planned',
          isDue: false,
        ),
        PlannedCost(
          plannedCostId: otherPlanId,
          accountId: _accountId,
          amount: '40.00',
          currency: 'EUR',
          title: 'Страховка',
          plannedOn: '2026-09-15',
          status: 'planned',
          isDue: false,
        ),
      ],
      recurrences: [
        PlannedCostRecurrenceListItem(
          recurrence: _recurrence(),
          upcoming: const [
            PlannedCostRecurrenceInstance(
              plannedCostId: _planId,
              plannedOn: '2026-09-30',
            ),
          ],
        ),
      ],
      settleResult: FinanceEntrySuccess<PlannedCostSettled>(
        requestId: 'req_synthetic_planned_cost',
        value: const PlannedCostSettled(
          plannedCost: PlannedCost(
            plannedCostId: _planId,
            accountId: _accountId,
            amount: '800.00',
            currency: 'EUR',
            title: 'Аренда',
            plannedOn: '2026-09-30',
            status: 'skipped',
            isDue: false,
          ),
          idempotentReplay: false,
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    // A one-off plan gets no skip button: skipping it would mean exactly what
    // cancelling it means.
    expect(
      find.byKey(const Key('planned-cost-skip-$otherPlanId')),
      findsNothing,
    );

    await _tapAt(tester, const Key('planned-cost-skip-$_planId'));

    expect(repository.settled, [_planId]);
    expect(repository.transitions, [PlannedCostTransition.skip]);
  });

  testWidgets('ending a series asks first and then drops the rule', (
    tester,
  ) async {
    final repository = _FakeRepository(
      recurrences: [
        PlannedCostRecurrenceListItem(
          recurrence: _recurrence(),
          upcoming: const [],
        ),
      ],
      endRecurrenceResult: FinanceEntrySuccess<PlannedCostRecurrenceEnded>(
        requestId: 'req_synthetic_recurrence',
        value: PlannedCostRecurrenceEnded(
          recurrence: _recurrence(status: PlannedCostRecurrenceStatus.ended),
          cancelledOccurrences: 2,
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    await _tapAt(tester, const Key('end-recurrence-$_recurrenceId'));
    // Ending a series withdraws future payments, so it is never one tap.
    expect(repository.endedRecurrences, isEmpty);
    await tester.tap(find.byKey(const Key('confirm-end-recurrence')));
    await tester.pumpAndSettle();

    expect(repository.endedRecurrences, [_recurrenceId]);
    await tester.scrollUntilVisible(
      find.byKey(const Key('planned-cost-recurrence-empty')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('planned-cost-recurrence-empty')),
      findsOneWidget,
    );
  });

  testWidgets('a repeating form fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpPage(
      tester,
      repository: _FakeRepository(
        recurrences: [
          PlannedCostRecurrenceListItem(
            recurrence: _recurrence(),
            upcoming: const [],
          ),
        ],
      ),
      textScale: 2,
    );

    await _tapAt(tester, const Key('planned-cost-repeat'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('end-recurrence-$_recurrenceId')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  // A bill can be planned in any wallet the profile holds (ADR 0029). Without
  // a picker every plan landed on the default wallet, so a hryvnia rent could
  // not be recorded as an obligation at all.
  testWidgets('one wallet offers no choice', (tester) async {
    await _pumpPage(tester, repository: _FakeRepository());

    expect(find.byKey(const Key('planned-cost-wallet')), findsNothing);
  });

  testWidgets('a plan is written against the wallet that will pay it', (
    tester,
  ) async {
    final repository = _FakeRepository(
      extraWallet: true,
      createResult: FinanceEntrySuccess<PlannedCostCreated>(
        requestId: 'req_synthetic_planned_cost',
        value: const PlannedCostCreated(
          plannedCost: PlannedCost(
            plannedCostId: _planId,
            accountId: _hryvniaAccountId,
            amount: '1200.00',
            currency: 'UAH',
            title: 'Интернет',
            plannedOn: '2026-09-01',
            status: 'planned',
            isDue: false,
          ),
          idempotentReplay: false,
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    expect(find.byKey(const Key('planned-cost-wallet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('planned-cost-title')),
      'Интернет',
    );
    await tester.enterText(
      find.byKey(const Key('planned-cost-amount')),
      '1200.00',
    );
    await _tapAt(tester, const Key('planned-cost-wallet'));
    await tester.tap(find.text('Гривна · UAH').last);
    await tester.pumpAndSettle();
    await _tapAt(tester, const Key('planned-cost-submit'));

    // Switching wallets chooses where the bill is paid from; it does not
    // start the form again.
    final draft = repository.drafts.single;
    expect(draft.accountId, _hryvniaAccountId);
    expect(draft.currency, 'UAH');
    expect(draft.title, 'Интернет');
    expect(draft.amount, '1200.00');
  });
}

PlannedCostRecurrence _recurrence({
  PlannedCostRecurrenceStatus status = PlannedCostRecurrenceStatus.active,
}) {
  return PlannedCostRecurrence(
    recurrenceId: _recurrenceId,
    accountId: _accountId,
    amount: '800.00',
    currency: 'EUR',
    title: 'Аренда',
    dayOfMonth: 31,
    startsOn: '2026-08-09',
    status: status,
  );
}

/// Scrolls a control into view before tapping it.
///
/// The form is taller than a phone once the repeat controls and both lists are
/// on it, and a tap on an off-screen widget is not a user's experience of the
/// screen.
Future<void> _tapAt(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeRepository repository,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeEntryRepositoryProvider.overrideWithValue(repository),
        financeCommandIdFactoryProvider.overrideWithValue(() => _planCommandId),
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
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: PlannedCostPage(onSignInRequested: () async {}),
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
  createPlannedCostRecurrence(PlannedCostRecurrenceDraft draft) async {
    recurrenceDrafts.add(draft);
    final result = createRecurrenceResult;
    if (result == null) throw StateError('No recurrence result configured.');
    return result;
  }

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceList>>
  listPlannedCostRecurrences() async {
    return FinanceEntrySuccess<PlannedCostRecurrenceList>(
      requestId: 'req_synthetic_planned_cost',
      value: PlannedCostRecurrenceList(recurrences: recurrences),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceEnded>>
  endPlannedCostRecurrence(
    String recurrenceId,
    EndPlannedCostRecurrenceCommand command,
  ) async {
    endedRecurrences.add(recurrenceId);
    final result = endRecurrenceResult;
    if (result == null) throw StateError('No end result configured.');
    return result;
  }

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
  _FakeRepository({
    this.hasAccount = true,
    this.extraWallet = false,
    this.listFailure,
    this.createResult,
    this.plans = const [],
    this.settleResult,
    this.recurrences = const [],
    this.createRecurrenceResult,
    this.endRecurrenceResult,
  });

  final List<PlannedCost> plans;
  final FinanceEntryResult<PlannedCostSettled>? settleResult;
  final List<String> settled = [];
  final List<PlannedCostTransition> transitions = [];
  final bool hasAccount;

  /// A second wallet in another currency (ADR 0029).
  final bool extraWallet;
  final FinanceEntryFailure? listFailure;
  final FinanceEntryResult<PlannedCostCreated>? createResult;
  final List<PlannedCostDraft> drafts = [];
  final List<PlannedCostRecurrenceListItem> recurrences;
  final FinanceEntryResult<PlannedCostRecurrenceCreated>?
  createRecurrenceResult;
  final FinanceEntryResult<PlannedCostRecurrenceEnded>? endRecurrenceResult;
  final List<PlannedCostRecurrenceDraft> recurrenceDrafts = [];
  final List<String> endedRecurrences = [];
  int listCalls = 0;
  @override
  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts() async {
    return FinanceEntrySuccess<PlannedCostList>(
      requestId: 'req_synthetic_planned_cost',
      value: PlannedCostList(evaluatedOn: '2026-08-09', plans: plans),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostSettled>> transitionPlannedCost(
    String plannedCostId,
    PlannedCostTransitionCommand command,
  ) async {
    settled.add(plannedCostId);
    transitions.add(command.transition);
    final result = settleResult;
    if (result == null) throw UnimplementedError();
    return result;
  }

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    listCalls += 1;
    final failure = listFailure;
    if (failure != null) {
      return FinanceEntryFailureResult<FinanceAccountSetup>(failure);
    }
    return FinanceEntrySuccess<FinanceAccountSetup>(
      requestId: 'req_synthetic_planned_cost',
      value: FinanceAccountSetup(
        canonicalTimezone: hasAccount ? configuredHomeApiTimezone : null,
        timezoneRevision: hasAccount ? 1 : 0,
        accounts: hasAccount
            ? [
                FinanceAccount(
                  accountId: _accountId,
                  userId: _userId,
                  commandId: _accountCommandId,
                  name: 'Тестовый счёт',
                  currency: 'EUR',
                  openingBalance: '100.00',
                  openingBalanceOn: '2026-07-10',
                  openingTimezone: configuredHomeApiTimezone,
                  isDefault: true,
                  confirmedAt: '2026-07-10T10:00:00.000Z',
                  createdAt: '2026-07-10T10:00:00.000Z',
                ),
                if (extraWallet)
                  const FinanceAccount(
                    accountId: _hryvniaAccountId,
                    userId: _userId,
                    commandId: '88888888-8888-4888-8888-888888888888',
                    name: 'Гривна',
                    currency: 'UAH',
                    openingBalance: '0.00',
                    openingBalanceOn: '2026-07-12',
                    openingTimezone: configuredHomeApiTimezone,
                    isDefault: false,
                    confirmedAt: '2026-07-12T10:00:00.000Z',
                    createdAt: '2026-07-12T10:00:00.000Z',
                  ),
              ]
            : const [],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost(
    PlannedCostDraft draft,
  ) async {
    drafts.add(draft);
    final result = createResult;
    if (result == null) throw UnimplementedError();
    return result;
  }

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount(
    FinanceAccountDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount(
    FinanceAccountCommitCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline(
    FinanceBaselineDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline(
    FinanceBaselineCommitCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation(
    FinanceOperationCommitCommand command, {
    required String expectedPrincipalScopeId,
    required String expectedSessionRevision,
    required FinanceCommitPreflight preflight,
  }) => throw UnimplementedError();
}

class _FirstUseHome implements HomeRepository, HomeCacheInvalidator {
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

class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;

  @override
  Future<void> clearSession() async {}
}
