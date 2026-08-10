import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/planned_cost_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _accountCommandId = '33333333-3333-4333-8333-333333333333';
const _planCommandId = '44444444-4444-4444-8444-444444444444';
const _planId = '55555555-5555-4555-8555-555555555555';

void main() {
  group('PlannedCostController', () {
    test('bounds the picker by the account baseline, never before it', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(plannedCostControllerProvider.notifier).load();

      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      // A plan before the baseline could never be confirmed into an operation.
      expect(state.earliestDate, DateTime.utc(2026, 7, 10));
      expect(state.selectedDate, DateTime.utc(2026, 8, 9));
      // A forecast is allowed to sit far in the future; that is the point.
      expect(state.latestDate.isAfter(DateTime.utc(2030)), isTrue);
    });

    test('selecting a date before the baseline is refused locally', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();

      controller.selectDate(DateTime.utc(2026, 7, 9));

      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      expect(state.selectedDate, DateTime.utc(2026, 8, 9));
      expect(state.failure?.kind, FinanceEntryFailureKind.invalidInput);
      expect(repository.drafts, isEmpty);
    });

    test('submits a future-dated plan and reports Home convergence', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onCreate: (draft) => _success(
          PlannedCostCreated(
            plannedCost: _plan(plannedOn: draft.plannedOn),
            idempotentReplay: false,
          ),
        ),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();

      controller.setTitle('Аренда');
      controller.setAmount('800,50');
      controller.selectDate(DateTime.utc(2026, 9, 1));
      await controller.submit();

      final draft = repository.drafts.single;
      expect(draft.title, 'Аренда');
      // Russian keyboards produce a comma; the wire contract needs a dot.
      expect(draft.amount, '800.50');
      expect(draft.plannedOn, '2026-09-01');
      expect(draft.accountId, _accountId);
      expect(draft.commandId, _planCommandId);
      expect(
        container.read(plannedCostControllerProvider),
        isA<PlannedCostAccepted>(),
      );
    });

    test('a rejection surfaces its typed issue and keeps the input', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onCreate: (_) => _rejection(),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();
      controller.setTitle('Аренда');
      controller.setAmount('800.00');

      await controller.submit();

      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      expect(state.isSubmitting, isFalse);
      expect(state.title, 'Аренда');
      expect(
        state.issues.single.code,
        PlannedCostIssueCode.planBeforeAccountBaseline,
      );
    });

    test(
      'a retry replays the same command id rather than adding a plan',
      () async {
        var issued = 0;
        final repository = _FakeRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          onCreate: (_) => _rejection(),
        );
        final container = _container(
          repository,
          commandIdFactory: () {
            issued += 1;
            return _planCommandId;
          },
        );
        addTearDown(container.dispose);
        final controller = container.read(
          plannedCostControllerProvider.notifier,
        );
        await controller.load();
        controller.setTitle('Аренда');
        controller.setAmount('800.00');

        await controller.submit();
        await controller.submit();

        expect(repository.drafts, hasLength(2));
        expect(
          repository.drafts.first.commandId,
          repository.drafts.last.commandId,
        );
        expect(issued, 1);
      },
    );

    test('editing the input starts a new command', () async {
      var issued = 0;
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onCreate: (_) => _rejection(),
      );
      final container = _container(
        repository,
        commandIdFactory: () {
          issued += 1;
          return _planCommandId;
        },
      );
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();
      controller.setTitle('Аренда');
      controller.setAmount('800.00');
      await controller.submit();

      // Different content must not reuse the identity of the refused command.
      controller.setAmount('900.00');
      await controller.submit();

      expect(issued, 2);
    });

    test('an empty amount never reaches the network', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();
      controller.setTitle('Аренда');

      await controller.submit();

      expect(repository.drafts, isEmpty);
      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      expect(state.failure?.kind, FinanceEntryFailureKind.invalidInput);
    });

    test('an unauthorized failure asks for sign-in', () async {
      final repository = _FakeRepository(
        listResults: [
          _failureResult<FinanceAccountSetup>(
            FinanceEntryFailureKind.unauthorized,
          ),
        ],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(plannedCostControllerProvider.notifier).load();

      expect(
        container.read(plannedCostControllerProvider),
        isA<PlannedCostAuthenticationRequired>(),
      );
    });

    test('a user without an account is told to create one first', () async {
      final repository = _FakeRepository(
        listResults: [_success(_emptySetup())],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(plannedCostControllerProvider.notifier).load();

      final state =
          container.read(plannedCostControllerProvider)
              as PlannedCostUnavailable;
      expect(state.reason, PlannedCostUnavailableReason.accountRequired);
    });
  });
}

ProviderContainer _container(
  _FakeRepository repository, {
  String Function()? commandIdFactory,
}) {
  final container = ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      financeEntryClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 8, 9, 12),
      ),
      financeCommandIdFactoryProvider.overrideWithValue(
        commandIdFactory ?? () => _planCommandId,
      ),
      homeSessionStoreProvider.overrideWithValue(const _NullHomeSessionStore()),
      acceptedWriteHomeDelayProvider.overrideWithValue((_) async {}),
    ],
  );
  container.listen(
    plannedCostControllerProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return container;
}

FinanceEntrySuccess<T> _success<T>(T value) => FinanceEntrySuccess<T>(
  requestId: 'req_synthetic_planned_cost',
  value: value,
);

FinanceEntryFailureResult<T> _failureResult<T>(FinanceEntryFailureKind kind) =>
    FinanceEntryFailureResult<T>(
      FinanceEntryFailure(kind: kind, requestId: 'req_synthetic_planned_cost'),
    );

FinanceEntryFailureResult<PlannedCostCreated> _rejection() =>
    FinanceEntryFailureResult<PlannedCostCreated>(
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
    );

FinanceAccountSetup _setup(FinanceAccount account) => FinanceAccountSetup(
  canonicalTimezone: configuredHomeApiTimezone,
  timezoneRevision: 1,
  accounts: [account],
);

FinanceAccountSetup _emptySetup() => FinanceAccountSetup(
  canonicalTimezone: null,
  timezoneRevision: 0,
  accounts: const [],
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
  confirmedAt: '2026-07-10T10:00:00.000Z',
  createdAt: '2026-07-10T10:00:00.000Z',
);

PlannedCost _plan({required String plannedOn}) => PlannedCost(
  plannedCostId: _planId,
  accountId: _accountId,
  amount: '800.50',
  currency: 'EUR',
  title: 'Аренда',
  plannedOn: plannedOn,
  status: 'planned',
  isDue: false,
);

class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository({
    List<FinanceEntryResult<FinanceAccountSetup>> listResults = const [],
    this.onCreate,
  }) : _listResults = List.of(listResults);

  final List<FinanceEntryResult<FinanceAccountSetup>> _listResults;
  final FinanceEntryResult<PlannedCostCreated> Function(PlannedCostDraft)?
  onCreate;
  final List<PlannedCostDraft> drafts = [];

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    return _listResults.removeAt(0);
  }

  @override
  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost(
    PlannedCostDraft draft,
  ) async {
    drafts.add(draft);
    final handler = onCreate;
    if (handler == null) throw UnimplementedError();
    return handler(draft);
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

class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;

  @override
  Future<void> clearSession() async {}
}
