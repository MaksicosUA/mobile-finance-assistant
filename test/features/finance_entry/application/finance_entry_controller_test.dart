import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/core/platform/finance_capture_context.dart';
import 'package:mobile_finance_assistant/features/auth/application/auth_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/operation_sync_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/operation_outbox.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _accountCommandId = '33333333-3333-4333-8333-333333333333';
const _operationCommandId = '44444444-4444-4444-8444-444444444444';
const _replacementOperationCommandId = '66666666-6666-4666-8666-666666666666';
const _operationId = '55555555-5555-4555-8555-555555555555';
const _draftHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _fixedNow = DateTime.utc(2026, 7, 29, 12, 30);
final _defaultCaptureContext = _captureContext(
  capturedAtUtc: '2026-07-29T11:45:12.345Z',
  osTimezone: 'America/Los_Angeles',
  osLocalDate: '2026-07-29',
  canonicalLocalDate: '2026-07-29',
);

const _categoryId = '99999999-9999-4999-8999-999999999999';

void main() {
  group('FinanceEntryController', () {
    test(
      'autoDispose drops a sensitive review after its last listener',
      () async {
        final account = _account();
        final repository = _FakeFinanceEntryRepository(
          listResult: _success(_initializedAccountSetup(account)),
          onEvaluateOperation: (draft) => _success(
            FinanceOperationNeedsConfirmation(
              draft: draft,
              draftHash: _draftHash,
            ),
          ),
        );
        final container = _container(
          repository,
          commandIdFactory: () => _operationCommandId,
          keepFinanceControllerAlive: false,
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          financeEntryControllerProvider,
          (_, _) {},
          fireImmediately: true,
        );
        final controller = container.read(
          financeEntryControllerProvider.notifier,
        );
        await controller.load();
        await controller.evaluateOperation(
          OperationEntryInput(
            type: FinanceOperationType.expense,
            amount: '91.70',
            occurredOn: DateTime(2026, 7, 29),
          ),
        );
        expect(
          container.read(financeEntryControllerProvider),
          isA<FinanceOperationReviewing>(),
        );

        subscription.close();
        await container.pump();

        expect(container.exists(financeEntryControllerProvider), isFalse);
        final replacementSubscription = container.listen(
          financeEntryControllerProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(replacementSubscription.close);
        expect(
          container.read(financeEntryControllerProvider),
          isA<FinanceEntryLoading>(),
        );
      },
    );

    test('empty account GET opens the explicit account setup form', () async {
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_emptyAccountSetup()),
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(financeEntryControllerProvider.notifier).load();

      final state =
          container.read(financeEntryControllerProvider)
              as FinanceAccountEditing;
      expect(repository.listCalls, 1);
      expect(state.initialInput.name, isEmpty);
      expect(state.initialInput.openingBalance, '0');
      expect(state.initialInput.openingBalanceOn, DateTime.utc(2026, 7, 29));
      expect(state.latestOpeningDate, DateTime.utc(2026, 7, 29));
      expect(state.failure, isNull);
    });

    test('account evaluation exposes the canonical server review', () async {
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_emptyAccountSetup()),
        onEvaluateAccount: (draft) => _success(
          FinanceAccountNeedsConfirmation(
            draft: FinanceAccountDraft.fromJson(draft.toJson()),
            draftHash: _draftHash,
          ),
        ),
      );
      final container = _container(
        repository,
        commandIdFactory: () => _accountCommandId,
      );
      addTearDown(container.dispose);
      await container.read(financeEntryControllerProvider.notifier).load();

      await container
          .read(financeEntryControllerProvider.notifier)
          .evaluateAccount(
            AccountSetupInput(
              name: '  Тестовый счёт  ',
              openingBalance: '-12,50',
              openingBalanceOn: DateTime(2026, 7, 1),
            ),
          );

      final state =
          container.read(financeEntryControllerProvider)
              as FinanceAccountReviewing;
      final draft = state.review.draft;
      expect(repository.accountDrafts, hasLength(1));
      expect(draft.commandId, _accountCommandId);
      expect(draft.name, 'Тестовый счёт');
      expect(draft.currency, 'EUR');
      expect(draft.openingBalance, '-12.50');
      expect(draft.openingBalanceOn, '2026-07-01');
      expect(draft.canonicalTimezone, configuredHomeApiTimezone);
      expect(draft.toJson()['openingBalance'], isA<String>());
      expect(state.review.draftHash, _draftHash);
    });

    test(
      'account commit retry reuses the exact command and confirmedAt',
      () async {
        final account = _account();
        late final _FakeFinanceEntryRepository repository;
        repository = _FakeFinanceEntryRepository(
          listResult: _success(_emptyAccountSetup()),
          onEvaluateAccount: (draft) => _success(
            FinanceAccountNeedsConfirmation(
              draft: draft,
              draftHash: _draftHash,
            ),
          ),
          onCommitAccount: (command) {
            if (repository.accountCommands.length == 1) {
              return _failure<FinanceAccountCommit>(
                FinanceEntryFailureKind.serviceUnavailable,
              );
            }
            return _success(
              FinanceAccountCommit(
                idempotentReplay: false,
                canonicalTimezone: configuredHomeApiTimezone,
                timezoneRevision: 1,
                account: account,
              ),
            );
          },
        );
        final clock = _SequenceClock([
          DateTime.utc(2026, 7, 29, 8),
          DateTime.utc(2026, 7, 29, 9),
          DateTime.utc(2026, 7, 29, 10),
          DateTime.utc(2026, 7, 29, 11),
          DateTime.utc(2026, 7, 29, 12),
        ]);
        final container = _container(
          repository,
          clock: clock.call,
          commandIdFactory: () => _accountCommandId,
        );
        addTearDown(container.dispose);
        final controller = container.read(
          financeEntryControllerProvider.notifier,
        );
        await controller.load();
        await controller.evaluateAccount(
          AccountSetupInput(
            name: 'Тестовый счёт',
            openingBalance: '10.00',
            openingBalanceOn: DateTime(2026, 7, 1),
          ),
        );

        await controller.confirmAccount();
        final failed =
            container.read(financeEntryControllerProvider)
                as FinanceAccountReviewing;
        expect(
          failed.failure?.kind,
          FinanceEntryFailureKind.serviceUnavailable,
        );
        final firstCommand = repository.accountCommands.single;

        await controller.confirmAccount();

        expect(repository.accountCommands, hasLength(2));
        expect(repository.accountCommands[1], same(firstCommand));
        expect(repository.accountCommands[1].toJson(), firstCommand.toJson());
        expect(firstCommand.confirmedAt, '2026-07-29T08:00:00.000Z');
        expect(clock.calls, 1);
        final ready =
            container.read(financeEntryControllerProvider)
                as FinanceOperationEditing;
        expect(ready.accountCreated, isTrue);
        expect(ready.account, same(account));
      },
    );

    test(
      'accepted account starts Home convergence without blocking operation form',
      () async {
        final account = _account();
        final repository = _FakeFinanceEntryRepository(
          listResult: _success(_emptyAccountSetup()),
          onEvaluateAccount: (draft) => _success(
            FinanceAccountNeedsConfirmation(
              draft: draft,
              draftHash: _draftHash,
            ),
          ),
          onCommitAccount: (_) => _success(
            FinanceAccountCommit(
              idempotentReplay: false,
              canonicalTimezone: configuredHomeApiTimezone,
              timezoneRevision: 1,
              account: account,
            ),
          ),
        );
        final homeRepository = _BlockingInvalidationHomeRepository();
        addTearDown(homeRepository.releaseInvalidation);
        final container = _container(
          repository,
          commandIdFactory: () => _accountCommandId,
          homeRepository: homeRepository,
        );
        addTearDown(container.dispose);
        final controller = container.read(
          financeEntryControllerProvider.notifier,
        );
        await controller.load();
        await controller.evaluateAccount(
          AccountSetupInput(
            name: 'Тестовый счёт',
            openingBalance: '10.00',
            openingBalanceOn: DateTime(2026, 7, 1),
          ),
        );

        await controller.confirmAccount().timeout(const Duration(seconds: 1));

        final state =
            container.read(financeEntryControllerProvider)
                as FinanceOperationEditing;
        expect(state.accountCreated, isTrue);
        expect(state.account, same(account));
        expect(homeRepository.invalidations, 1);
        expect(homeRepository.invalidationReleased, isFalse);
        expect(homeRepository.calls, 0);

        homeRepository.releaseInvalidation();
        await pumpEventQueue();
        expect(homeRepository.calls, 1);
      },
    );

    test('account epoch ignores a late accepted account commit', () async {
      final account = _account();
      final commitResult =
          Completer<FinanceEntryResult<FinanceAccountCommit>>();
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_emptyAccountSetup()),
        onEvaluateAccount: (draft) => _success(
          FinanceAccountNeedsConfirmation(draft: draft, draftHash: _draftHash),
        ),
        onCommitAccount: (_) => commitResult.future,
      );
      final homeRepository = _ProjectionLagHomeRepository();
      final container = _container(
        repository,
        commandIdFactory: () => _accountCommandId,
        homeRepository: homeRepository,
      );
      addTearDown(container.dispose);
      final controller = container.read(
        financeEntryControllerProvider.notifier,
      );
      await controller.load();
      await controller.evaluateAccount(
        AccountSetupInput(
          name: 'Тестовый счёт',
          openingBalance: '10.00',
          openingBalanceOn: DateTime(2026, 7, 1),
        ),
      );

      final pendingCommit = controller.confirmAccount();
      expect(repository.accountCommands, hasLength(1));
      container.read(authAccountEpochProvider.notifier).advance();
      await container.pump();
      expect(
        container.read(financeEntryControllerProvider),
        isA<FinanceEntryLoading>(),
      );

      commitResult.complete(
        _success(
          FinanceAccountCommit(
            idempotentReplay: false,
            canonicalTimezone: configuredHomeApiTimezone,
            timezoneRevision: 1,
            account: account,
          ),
        ),
      );
      await pendingCommit;

      expect(
        container.read(financeEntryControllerProvider),
        isA<FinanceEntryLoading>(),
      );
      expect(homeRepository.invalidations, 0);
      expect(homeRepository.calls, 0);
    });

    test('existing authoritative account opens operation form', () async {
      final account = _account();
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_initializedAccountSetup(account)),
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(financeEntryControllerProvider.notifier).load();

      final state =
          container.read(financeEntryControllerProvider)
              as FinanceOperationEditing;
      expect(state.account, same(account));
      expect(state.accountCreated, isFalse);
      expect(state.initialInput.type, FinanceOperationType.expense);
      expect(state.initialInput.amount, isEmpty);
      expect(state.initialInput.occurredOn, DateTime.utc(2026, 7, 29));
      expect(state.latestOperationDate, DateTime.utc(2026, 7, 29));
    });

    test(
      'near midnight uses canonical date for account and OS date for operation',
      () async {
        final source = _FixedFinanceCaptureContextSource(
          _captureContext(
            capturedAtUtc: '2026-07-29T00:30:00.000Z',
            osTimezone: 'America/Los_Angeles',
            osLocalDate: '2026-07-28',
            canonicalLocalDate: '2026-07-29',
          ),
        );
        final emptyRepository = _FakeFinanceEntryRepository(
          listResult: _success(_emptyAccountSetup()),
        );
        final emptyContainer = _container(
          emptyRepository,
          captureContextSource: source,
        );
        addTearDown(emptyContainer.dispose);

        await emptyContainer
            .read(financeEntryControllerProvider.notifier)
            .load();

        final accountState =
            emptyContainer.read(financeEntryControllerProvider)
                as FinanceAccountEditing;
        expect(
          accountState.initialInput.openingBalanceOn,
          DateTime.utc(2026, 7, 29),
        );
        expect(accountState.latestOpeningDate, DateTime.utc(2026, 7, 29));

        final operationRepository = _FakeFinanceEntryRepository(
          listResult: _success(_initializedAccountSetup(_account())),
        );
        final operationContainer = _container(
          operationRepository,
          captureContextSource: source,
        );
        addTearDown(operationContainer.dispose);

        await operationContainer
            .read(financeEntryControllerProvider.notifier)
            .load();

        final operationState =
            operationContainer.read(financeEntryControllerProvider)
                as FinanceOperationEditing;
        expect(
          operationState.initialInput.occurredOn,
          DateTime.utc(2026, 7, 28),
        );
        expect(operationState.latestOperationDate, DateTime.utc(2026, 7, 28));
        expect(source.canonicalTimezoneRequests, [
          configuredHomeApiTimezone,
          configuredHomeApiTimezone,
        ]);
      },
    );

    test(
      'future relative to OS date is rejected before operation API call',
      () async {
        final source = _FixedFinanceCaptureContextSource(
          _captureContext(
            capturedAtUtc: '2026-07-29T00:30:00.000Z',
            osTimezone: 'America/Los_Angeles',
            osLocalDate: '2026-07-28',
            canonicalLocalDate: '2026-07-29',
          ),
        );
        final repository = _FakeFinanceEntryRepository(
          listResult: _success(_initializedAccountSetup(_account())),
        );
        final container = _container(repository, captureContextSource: source);
        addTearDown(container.dispose);
        final controller = container.read(
          financeEntryControllerProvider.notifier,
        );
        await controller.load();

        await controller.evaluateOperation(
          OperationEntryInput(
            type: FinanceOperationType.expense,
            amount: '3.40',
            occurredOn: DateTime.utc(2026, 7, 29),
          ),
        );

        final state =
            container.read(financeEntryControllerProvider)
                as FinanceOperationEditing;
        expect(state.failure?.kind, FinanceEntryFailureKind.invalidInput);
        expect(state.latestOperationDate, DateTime.utc(2026, 7, 28));
        expect(repository.operationDrafts, isEmpty);
        expect(source.calls, 2);
      },
    );

    test(
      'operation evaluation sends explicit account and deterministic context',
      () async {
        final account = _account();
        final repository = _FakeFinanceEntryRepository(
          listResult: _success(_initializedAccountSetup(account)),
          onEvaluateOperation: (draft) => _success(
            FinanceOperationNeedsConfirmation(
              draft: draft,
              draftHash: _draftHash,
            ),
          ),
        );
        final container = _container(
          repository,
          commandIdFactory: () => _operationCommandId,
        );
        addTearDown(container.dispose);
        final controller = container.read(
          financeEntryControllerProvider.notifier,
        );
        await controller.load();

        await controller.evaluateOperation(
          OperationEntryInput(
            type: FinanceOperationType.expense,
            amount: '35,00',
            occurredOn: DateTime(2026, 7, 28),
            category: '  Тестовая категория  ',
            merchant: '  Тестовый магазин  ',
          ),
        );

        final state =
            container.read(financeEntryControllerProvider)
                as FinanceOperationReviewing;
        final draft = state.review.draft;
        expect(repository.operationDrafts, hasLength(1));
        expect(draft.commandId, _operationCommandId);
        expect(draft.accountId, _accountId);
        expect(draft.currency, 'EUR');
        expect(draft.amount, '35.00');
        expect(draft.source, FinanceOperationSource.manualText);
        expect(draft.toJson()['source'], 'manual_text');
        expect(draft.capturedAt, '2026-07-29T11:45:12.345Z');
        expect(draft.capturedTimezone, 'America/Los_Angeles');
        expect(draft.occurredOn, '2026-07-28');
        expect(draft.occurredAt, isNull);
        expect(draft.sourceExpression, isNull);
        expect(draft.category, 'Тестовая категория');
        expect(draft.merchant, 'Тестовый магазин');
      },
    );

    test('operation REJECT keeps the submitted values editable', () async {
      final account = _account();
      const issue = FinanceIssue(
        code: FinanceIssueCode.accountUnavailable,
        field: FinanceIssueField.accountId,
      );
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_initializedAccountSetup(account)),
        onEvaluateOperation: (draft) => _success(
          FinanceOperationRejected(draft: draft, issues: const [issue]),
        ),
      );
      final container = _container(
        repository,
        commandIdFactory: () => _operationCommandId,
      );
      addTearDown(container.dispose);
      final controller = container.read(
        financeEntryControllerProvider.notifier,
      );
      await controller.load();
      final input = OperationEntryInput(
        type: FinanceOperationType.income,
        amount: '8.75',
        occurredOn: DateTime(2026, 7, 28),
      );

      await controller.evaluateOperation(input);

      final state =
          container.read(financeEntryControllerProvider)
              as FinanceOperationEditing;
      expect(state.initialInput, same(input));
      expect(state.isSubmitting, isFalse);
      expect(state.failure, isNull);
      expect(state.issues, const [issue]);
    });

    test(
      'accepted operation remains accepted when Home projection is delayed',
      () async {
        final account = _account();
        final repository = _FakeFinanceEntryRepository(
          listResult: _success(_initializedAccountSetup(account)),
          onEvaluateOperation: (draft) => _success(
            FinanceOperationNeedsConfirmation(
              draft: draft,
              draftHash: _draftHash,
            ),
          ),
        );
        final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
          (_, command) => OperationDeliveryAccepted(
            homeStatus: AcceptedWriteHomeConvergenceResult.projectionDelayed,
            commit: FinanceOperationCommit(
              idempotentReplay: false,
              operation: _committedOperation(command),
            ),
          ),
        );
        final container = _container(
          repository,
          commandIdFactory: () => _operationCommandId,
          operationDeliveryCoordinator: deliveryCoordinator,
        );
        addTearDown(container.dispose);
        final controller = container.read(
          financeEntryControllerProvider.notifier,
        );
        await controller.load();
        await controller.evaluateOperation(
          OperationEntryInput(
            type: FinanceOperationType.expense,
            amount: '7.25',
            occurredOn: DateTime(2026, 7, 29),
          ),
        );

        await controller.confirmOperation();

        final state =
            container.read(financeEntryControllerProvider)
                as FinanceOperationAccepted;
        expect(state.operation.operationId, _operationId);
        expect(state.homeStatus, FinanceEntryHomeStatus.projectionDelayed);
        expect(state.homeStatus, isNot(FinanceEntryHomeStatus.failed));
        expect(deliveryCoordinator.calls, hasLength(1));
        expect(deliveryCoordinator.calls.single.principalScopeId, _userId);
        expect(
          deliveryCoordinator.calls.single.command.review.draft.amount,
          '7.25',
        );
      },
    );

    test('account epoch ignores a late accepted operation commit', () async {
      final account = _account();
      final deliveryResult = Completer<OperationDeliveryResult>();
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_initializedAccountSetup(account)),
        onEvaluateOperation: (draft) => _success(
          FinanceOperationNeedsConfirmation(
            draft: draft,
            draftHash: _draftHash,
          ),
        ),
      );
      final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
        (_, _) => deliveryResult.future,
      );
      final container = _container(
        repository,
        commandIdFactory: () => _operationCommandId,
        operationDeliveryCoordinator: deliveryCoordinator,
      );
      addTearDown(container.dispose);
      final controller = container.read(
        financeEntryControllerProvider.notifier,
      );
      await controller.load();
      await controller.evaluateOperation(
        OperationEntryInput(
          type: FinanceOperationType.expense,
          amount: '16.40',
          occurredOn: DateTime(2026, 7, 29),
        ),
      );

      final pendingCommit = controller.confirmOperation();
      expect(deliveryCoordinator.calls, hasLength(1));
      container.read(authAccountEpochProvider.notifier).advance();
      await container.pump();
      expect(
        container.read(financeEntryControllerProvider),
        isA<FinanceEntryLoading>(),
      );

      deliveryResult.complete(
        OperationDeliveryAccepted(
          homeStatus: AcceptedWriteHomeConvergenceResult.updated,
          commit: FinanceOperationCommit(
            idempotentReplay: false,
            operation: _committedOperation(
              deliveryCoordinator.calls.single.command,
            ),
          ),
        ),
      );
      await pendingCommit;

      expect(
        container.read(financeEntryControllerProvider),
        isA<FinanceEntryLoading>(),
      );
    });

    test(
      'accepted delivery maps failed Home convergence without retrying',
      () async {
        final account = _account();
        final repository = _FakeFinanceEntryRepository(
          listResult: _success(_initializedAccountSetup(account)),
          onEvaluateOperation: (draft) => _success(
            FinanceOperationNeedsConfirmation(
              draft: draft,
              draftHash: _draftHash,
            ),
          ),
        );
        final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
          (_, command) => OperationDeliveryAccepted(
            homeStatus: AcceptedWriteHomeConvergenceResult.failed,
            commit: FinanceOperationCommit(
              idempotentReplay: false,
              operation: _committedOperation(command),
            ),
          ),
        );
        final container = _container(
          repository,
          commandIdFactory: () => _operationCommandId,
          operationDeliveryCoordinator: deliveryCoordinator,
        );
        addTearDown(container.dispose);
        final controller = container.read(
          financeEntryControllerProvider.notifier,
        );
        await controller.load();
        await controller.evaluateOperation(
          OperationEntryInput(
            type: FinanceOperationType.expense,
            amount: '5.80',
            occurredOn: DateTime(2026, 7, 29),
          ),
        );

        await controller.confirmOperation();

        final state =
            container.read(financeEntryControllerProvider)
                as FinanceOperationAccepted;
        expect(state.operation.operationId, _operationId);
        expect(state.homeStatus, FinanceEntryHomeStatus.failed);
        expect(deliveryCoordinator.calls, hasLength(1));
      },
    );

    test('local storage failure keeps the exact review retryable', () async {
      final account = _account();
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_initializedAccountSetup(account)),
        onEvaluateOperation: (draft) => _success(
          FinanceOperationNeedsConfirmation(
            draft: draft,
            draftHash: _draftHash,
          ),
        ),
      );
      final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
        (_, _) => const OperationDeliveryStorageFailure(
          OperationOutboxErrorCode.storageUnavailable,
        ),
      );
      final container = _container(
        repository,
        commandIdFactory: () => _operationCommandId,
        operationDeliveryCoordinator: deliveryCoordinator,
      );
      addTearDown(container.dispose);
      final controller = container.read(
        financeEntryControllerProvider.notifier,
      );
      await controller.load();
      await controller.evaluateOperation(
        OperationEntryInput(
          type: FinanceOperationType.expense,
          amount: '9.90',
          occurredOn: DateTime(2026, 7, 29),
        ),
      );

      await controller.confirmOperation();

      final state =
          container.read(financeEntryControllerProvider)
              as FinanceOperationReviewing;
      expect(state.review.draft.amount, '9.90');
      expect(state.failure?.kind, FinanceEntryFailureKind.localStorage);
      expect(state.isSubmitting, isFalse);
      expect(deliveryCoordinator.calls, hasLength(1));
    });

    test('permanent delivery failure maps to user attention', () async {
      final account = _account();
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_initializedAccountSetup(account)),
        onEvaluateOperation: (draft) => _success(
          FinanceOperationNeedsConfirmation(
            draft: draft,
            draftHash: _draftHash,
          ),
        ),
      );
      final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
        (_, _) => const OperationDeliveryPermanentFailure(
          OperationOutboxErrorCode.securityBlocked,
        ),
      );
      final container = _container(
        repository,
        commandIdFactory: () => _operationCommandId,
        operationDeliveryCoordinator: deliveryCoordinator,
      );
      addTearDown(container.dispose);
      final controller = container.read(
        financeEntryControllerProvider.notifier,
      );
      await controller.load();
      await controller.evaluateOperation(
        OperationEntryInput(
          type: FinanceOperationType.expense,
          amount: '12.30',
          occurredOn: DateTime(2026, 7, 29),
        ),
      );

      await controller.confirmOperation();

      final state =
          container.read(financeEntryControllerProvider)
              as FinanceOperationDeliveryAttention;
      expect(state.issue, FinanceOperationDeliveryIssue.securityBlocked);
      expect(deliveryCoordinator.calls, hasLength(1));

      controller.addAnotherOperation();
      expect(container.read(financeEntryControllerProvider), same(state));
    });

    for (final kind in const [
      FinanceEntryFailureKind.unauthenticated,
      FinanceEntryFailureKind.unauthorized,
    ]) {
      test('load maps ${kind.name} to authentication-required', () async {
        final repository = _FakeFinanceEntryRepository(
          listResult: _failure<FinanceAccountSetup>(kind),
        );
        final container = _container(repository);
        addTearDown(container.dispose);

        await container.read(financeEntryControllerProvider.notifier).load();

        expect(
          container.read(financeEntryControllerProvider),
          isA<FinanceEntryAuthenticationRequired>(),
        );
      });
    }

    test(
      'session change during load remains a retryable load failure',
      () async {
        final repository = _FakeFinanceEntryRepository(
          listResult: _failure<FinanceAccountSetup>(
            FinanceEntryFailureKind.sessionChanged,
          ),
        );
        final container = _container(repository);
        addTearDown(container.dispose);

        await container.read(financeEntryControllerProvider.notifier).load();

        final state =
            container.read(financeEntryControllerProvider)
                as FinanceEntryLoadFailure;
        expect(state.failure.kind, FinanceEntryFailureKind.sessionChanged);
      },
    );

    test(
      'queued auth failure discards review and never retries command',
      () async {
        final account = _account();
        final commandIds = [
          _operationCommandId,
          _replacementOperationCommandId,
        ];
        var commandIdIndex = 0;
        final repository = _FakeFinanceEntryRepository(
          listResult: _success(_initializedAccountSetup(account)),
          onEvaluateOperation: (draft) => _success(
            FinanceOperationNeedsConfirmation(
              draft: draft,
              draftHash: _draftHash,
            ),
          ),
        );
        final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
          (_, _) => const OperationDeliveryQueued(
            code: OperationOutboxErrorCode.sessionChanged,
          ),
        );
        final container = _container(
          repository,
          commandIdFactory: () => commandIds[commandIdIndex++],
          operationDeliveryCoordinator: deliveryCoordinator,
        );
        addTearDown(container.dispose);
        final controller = container.read(
          financeEntryControllerProvider.notifier,
        );
        await controller.load();
        await controller.evaluateOperation(
          OperationEntryInput(
            type: FinanceOperationType.expense,
            amount: '4.20',
            occurredOn: DateTime(2026, 7, 29),
          ),
        );

        await controller.confirmOperation();

        final queued =
            container.read(financeEntryControllerProvider)
                as FinanceOperationQueued;
        expect(queued.authenticationRequired, isTrue);
        expect(deliveryCoordinator.calls, hasLength(1));
        expect(
          deliveryCoordinator.calls.single.command.review.draft.amount,
          '4.20',
        );

        await controller.confirmOperation();

        expect(deliveryCoordinator.calls, hasLength(1));
        await controller.load();
        final fresh =
            container.read(financeEntryControllerProvider)
                as FinanceOperationEditing;
        expect(fresh.initialInput.amount, isEmpty);
        expect(fresh.failure, isNull);
        expect(commandIdIndex, 1);
      },
    );

    test('accepted delivery maps a Home session change separately', () async {
      final account = _account();
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_initializedAccountSetup(account)),
        onEvaluateOperation: (draft) => _success(
          FinanceOperationNeedsConfirmation(
            draft: draft,
            draftHash: _draftHash,
          ),
        ),
      );
      final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
        (_, command) => OperationDeliveryAccepted(
          homeStatus: AcceptedWriteHomeConvergenceResult.sessionChanged,
          commit: FinanceOperationCommit(
            idempotentReplay: false,
            operation: _committedOperation(command),
          ),
        ),
      );
      final container = _container(
        repository,
        commandIdFactory: () => _operationCommandId,
        operationDeliveryCoordinator: deliveryCoordinator,
      );
      addTearDown(container.dispose);
      final controller = container.read(
        financeEntryControllerProvider.notifier,
      );
      await controller.load();
      await controller.evaluateOperation(
        OperationEntryInput(
          type: FinanceOperationType.expense,
          amount: '6.10',
          occurredOn: DateTime(2026, 7, 29),
        ),
      );

      await controller.confirmOperation();

      final state =
          container.read(financeEntryControllerProvider)
              as FinanceOperationAccepted;
      expect(state.homeStatus, FinanceEntryHomeStatus.sessionChanged);
      expect(deliveryCoordinator.calls, hasLength(1));
    });
  });

  group('category link (ADR 0020)', () {
    test('a chosen category reaches the draft beside its name', () async {
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_initializedAccountSetup(_account())),
        onEvaluateOperation: (draft) => _success(
          FinanceOperationNeedsConfirmation(
            draft: draft,
            draftHash: _draftHash,
          ),
        ),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(
        financeEntryControllerProvider.notifier,
      );
      await controller.load();

      await controller.evaluateOperation(
        OperationEntryInput(
          type: FinanceOperationType.expense,
          amount: '25.00',
          occurredOn: DateTime(2026, 7, 29),
          category: 'Продукты',
          categoryId: _categoryId,
        ),
      );

      final draft = repository.operationDrafts.single;
      expect(draft.categoryId, _categoryId);
      // The text is the evidence of what the user chose and travels with it.
      expect(draft.category, 'Продукты');
    });

    test('free text keeps working with no link at all', () async {
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_initializedAccountSetup(_account())),
        onEvaluateOperation: (draft) => _success(
          FinanceOperationNeedsConfirmation(
            draft: draft,
            draftHash: _draftHash,
          ),
        ),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(
        financeEntryControllerProvider.notifier,
      );
      await controller.load();

      await controller.evaluateOperation(
        OperationEntryInput(
          type: FinanceOperationType.expense,
          amount: '25.00',
          occurredOn: DateTime(2026, 7, 29),
          category: 'Что-то своё',
        ),
      );

      final draft = repository.operationDrafts.single;
      expect(draft.categoryId, isNull);
      expect(draft.category, 'Что-то своё');
    });

    test('a link without a name is refused before any request', () async {
      // A grouped operation with no record of what the user chose would make a
      // wrong link impossible to see later.
      final repository = _FakeFinanceEntryRepository(
        listResult: _success(_initializedAccountSetup(_account())),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(
        financeEntryControllerProvider.notifier,
      );
      await controller.load();

      await controller.evaluateOperation(
        OperationEntryInput(
          type: FinanceOperationType.expense,
          amount: '25.00',
          occurredOn: DateTime(2026, 7, 29),
          categoryId: _categoryId,
        ),
      );

      final state =
          container.read(financeEntryControllerProvider)
              as FinanceOperationEditing;
      expect(state.failure?.kind, FinanceEntryFailureKind.invalidInput);
      expect(repository.operationDrafts, isEmpty);
    });
  });

  group('money input boundary', () {
    test('operation amount rejects zero and floating-point notation', () {
      for (final value in const ['0', '0.0', '0,000', '1e2', 'NaN']) {
        expect(
          () => normalizeMoneyInput(value),
          throwsA(isA<FormatException>()),
          reason: value,
        );
      }
      expect(normalizeMoneyInput('0,01'), '0.01');
    });

    test('wire contract rejects a JSON number instead of a decimal string', () {
      final json = _validOperationDraftJson()..['amount'] = 35.0;

      expect(
        () => FinanceOperationDraft.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

ProviderContainer _container(
  _FakeFinanceEntryRepository repository, {
  DateTime Function()? clock,
  String Function()? commandIdFactory,
  FinanceCaptureContextSource? captureContextSource,
  HomeRepository? homeRepository,
  AcceptedWriteHomeDelay? acceptedWriteDelay,
  OperationDeliveryCoordinator? operationDeliveryCoordinator,
  bool keepFinanceControllerAlive = true,
  bool throwOnHomeRepositoryRead = false,
}) {
  final container = ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      financeEntryClockProvider.overrideWithValue(clock ?? () => _fixedNow),
      financeCommandIdFactoryProvider.overrideWithValue(
        commandIdFactory ?? () => _operationCommandId,
      ),
      financeCaptureContextSourceProvider.overrideWithValue(
        captureContextSource ??
            _FixedFinanceCaptureContextSource(_defaultCaptureContext),
      ),
      if (throwOnHomeRepositoryRead)
        homeRepositoryProvider.overrideWith(
          (_) => throw StateError('Unexpected Home convergence failure.'),
        )
      else if (homeRepository != null)
        homeRepositoryProvider.overrideWithValue(homeRepository),
      homeSessionStoreProvider.overrideWithValue(const _NullHomeSessionStore()),
      acceptedWriteHomeDelayProvider.overrideWithValue(
        acceptedWriteDelay ?? (_) async {},
      ),
      if (operationDeliveryCoordinator != null)
        operationDeliveryCoordinatorProvider.overrideWithValue(
          operationDeliveryCoordinator,
        ),
    ],
  );
  if (keepFinanceControllerAlive) {
    container.listen(
      financeEntryControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
  }
  return container;
}

FinanceCaptureContext _captureContext({
  required String capturedAtUtc,
  required String osTimezone,
  required String osLocalDate,
  required String canonicalLocalDate,
}) {
  return FinanceCaptureContext.fromPlatformValue({
    'capturedAtUtc': capturedAtUtc,
    'osTimezone': osTimezone,
    'osLocalDate': osLocalDate,
    'canonicalTimezone': configuredHomeApiTimezone,
    'canonicalLocalDate': canonicalLocalDate,
  }, expectedCanonicalTimezone: configuredHomeApiTimezone);
}

FinanceEntrySuccess<T> _success<T>(T value) => FinanceEntrySuccess<T>(
  requestId: 'req_synthetic_finance_entry',
  value: value,
);

FinanceEntryFailureResult<T> _failure<T>(FinanceEntryFailureKind kind) {
  return FinanceEntryFailureResult<T>(
    FinanceEntryFailure(
      kind: kind,
      requestId: 'req_synthetic_finance_entry_failure',
    ),
  );
}

FinanceAccountSetup _emptyAccountSetup() => FinanceAccountSetup(
  canonicalTimezone: null,
  timezoneRevision: 0,
  accounts: const [],
);

FinanceAccountSetup _initializedAccountSetup(FinanceAccount account) {
  return FinanceAccountSetup(
    canonicalTimezone: configuredHomeApiTimezone,
    timezoneRevision: 1,
    accounts: [account],
  );
}

FinanceAccount _account() => const FinanceAccount(
  accountId: _accountId,
  userId: _userId,
  commandId: _accountCommandId,
  name: 'Тестовый счёт',
  currency: 'EUR',
  openingBalance: '10.00',
  openingBalanceOn: '2026-07-01',
  openingTimezone: configuredHomeApiTimezone,
  isDefault: true,
  confirmedAt: '2026-07-01T08:00:00.000Z',
  createdAt: '2026-07-01T08:00:01.000Z',
);

CommittedFinanceOperation _committedOperation(
  FinanceOperationCommitCommand command,
) {
  final draft = command.review.draft;
  return CommittedFinanceOperation(
    operationId: _operationId,
    userId: _userId,
    commandId: draft.commandId,
    type: draft.type,
    amount: draft.amount,
    currency: draft.currency,
    accountId: draft.accountId,
    category: draft.category,
    categoryId: null,
    merchant: draft.merchant,
    capturedAt: draft.capturedAt,
    capturedTimezone: draft.capturedTimezone,
    sourceExpression: draft.sourceExpression,
    dateResolverVersion: draft.dateResolverVersion,
    occurredOn: draft.occurredOn,
    occurredAt: draft.occurredAt,
    source: draft.source,
    confirmedAt: command.confirmedAt,
    createdAt: '2026-07-29T12:31:00.000Z',
  );
}

Map<String, Object?> _validOperationDraftJson() => <String, Object?>{
  'schemaVersion': '1',
  'commandId': _operationCommandId,
  'type': 'expense',
  'amount': '35.00',
  'currency': 'EUR',
  'accountId': _accountId,
  'category': null,
  'merchant': null,
  'capturedAt': '2026-07-29T12:30:00.000Z',
  'capturedTimezone': configuredHomeApiTimezone,
  'sourceExpression': null,
  'dateResolverVersion': 'calendar-relative-v1',
  'occurredOn': '2026-07-28',
  'occurredAt': null,
  'source': 'manual_text',
};

typedef _AccountEvaluationHandler =
    FutureOr<FinanceEntryResult<FinanceAccountEvaluation>> Function(
      FinanceAccountDraft draft,
    );
typedef _AccountCommitHandler =
    FutureOr<FinanceEntryResult<FinanceAccountCommit>> Function(
      FinanceAccountCommitCommand command,
    );
typedef _OperationEvaluationHandler =
    FutureOr<FinanceEntryResult<FinanceOperationEvaluation>> Function(
      FinanceOperationDraft draft,
    );
typedef _OperationDeliveryHandler =
    FutureOr<OperationDeliveryResult> Function(
      String expectedPrincipalScopeId,
      FinanceOperationCommitCommand command,
    );

final class _FakeOperationDeliveryCoordinator
    implements OperationDeliveryCoordinator {
  _FakeOperationDeliveryCoordinator(this._handler);

  final _OperationDeliveryHandler _handler;
  final List<({String principalScopeId, FinanceOperationCommitCommand command})>
  calls = [];

  @override
  Future<OperationDeliveryResult> enqueueAndSynchronize({
    required String expectedPrincipalScopeId,
    required FinanceOperationCommitCommand command,
    void Function(FinanceOperationCommit commit)? onAccepted,
  }) async {
    calls.add((principalScopeId: expectedPrincipalScopeId, command: command));
    final result = await _handler(expectedPrincipalScopeId, command);
    if (result case OperationDeliveryAccepted(:final commit)) {
      onAccepted?.call(commit);
    }
    return result;
  }
}

final class _FakeFinanceEntryRepository
    implements FinanceEntryRepositoryClient {
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
  _FakeFinanceEntryRepository({
    required this.listResult,
    this.onEvaluateAccount,
    this.onCommitAccount,
    this.onEvaluateOperation,
  });

  final FinanceEntryResult<FinanceAccountSetup> listResult;
  final _AccountEvaluationHandler? onEvaluateAccount;
  final _AccountCommitHandler? onCommitAccount;
  final _OperationEvaluationHandler? onEvaluateOperation;
  final List<FinanceAccountDraft> accountDrafts = [];
  final List<FinanceAccountCommitCommand> accountCommands = [];
  final List<FinanceOperationDraft> operationDrafts = [];
  var listCalls = 0;
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
    return listResult;
  }

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount(
    FinanceAccountDraft draft,
  ) async {
    accountDrafts.add(draft);
    final handler = onEvaluateAccount;
    if (handler == null) throw StateError('Unexpected account evaluation.');
    return await handler(draft);
  }

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount(
    FinanceAccountCommitCommand command,
  ) async {
    accountCommands.add(command);
    final handler = onCommitAccount;
    if (handler == null) throw StateError('Unexpected account commit.');
    return await handler(command);
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline(
    FinanceBaselineDraft draft,
  ) {
    throw StateError('Unexpected baseline evaluation.');
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline(
    FinanceBaselineCommitCommand command,
  ) {
    throw StateError('Unexpected baseline commit.');
  }

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) async {
    operationDrafts.add(draft);
    final handler = onEvaluateOperation;
    if (handler == null) throw StateError('Unexpected operation evaluation.');
    return await handler(draft);
  }

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation(
    FinanceOperationCommitCommand command, {
    required String expectedPrincipalScopeId,
    required String expectedSessionRevision,
    required FinanceCommitPreflight preflight,
  }) async {
    final blocked = preflight();
    if (blocked != null) {
      return FinanceEntryFailureResult<FinanceOperationCommit>(
        FinanceEntryFailure(
          kind: blocked,
          requestId: 'req_test_preflight_blocked',
        ),
      );
    }
    throw StateError('Operation delivery must use the coordinator.');
  }
}

final class _SequenceClock {
  _SequenceClock(this.values);

  final List<DateTime> values;
  var calls = 0;

  DateTime call() => values[calls++];
}

final class _FixedFinanceCaptureContextSource
    implements FinanceCaptureContextSource {
  _FixedFinanceCaptureContextSource(this.context);

  final FinanceCaptureContext context;
  final List<String> canonicalTimezoneRequests = [];

  int get calls => canonicalTimezoneRequests.length;

  @override
  Future<FinanceCaptureContext> capture({
    required String canonicalTimezone,
  }) async {
    canonicalTimezoneRequests.add(canonicalTimezone);
    return context;
  }
}

final class _ProjectionLagHomeRepository
    implements HomeRepository, HomeCacheInvalidator {
  var calls = 0;
  var invalidations = 0;
  final List<bool> forceRefreshValues = [];

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    calls += 1;
    forceRefreshValues.add(forceRefresh);
    return HomeFailureResult(
      type: HomeFailureType.serviceUnavailable,
      requestId: 'req_synthetic_projection_$calls',
    );
  }

  @override
  Future<void> invalidateHomeCache() async {
    invalidations += 1;
  }
}

final class _BlockingInvalidationHomeRepository
    implements HomeRepository, HomeCacheInvalidator {
  final _invalidation = Completer<void>();
  var calls = 0;
  var invalidations = 0;

  bool get invalidationReleased => _invalidation.isCompleted;

  void releaseInvalidation() {
    if (!_invalidation.isCompleted) _invalidation.complete();
  }

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    calls += 1;
    return HomeFailureResult(
      type: HomeFailureType.unknown,
      requestId: 'req_synthetic_account_home_failure',
    );
  }

  @override
  Future<void> invalidateHomeCache() async {
    invalidations += 1;
    await _invalidation.future;
  }
}

final class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<void> clearSession() async {}

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;
}
