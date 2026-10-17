import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/core/platform/finance_capture_context.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/operation_sync_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/operation_outbox.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/finance_entry_page.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('account setup fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpPage(tester, repository: _FakeFinanceRepository(_emptySetup()));

    expect(find.byKey(const Key('account-name')), findsOneWidget);
    expect(find.byKey(const Key('opening-balance')), findsOneWidget);
    final dateFinder = find.byKey(const Key('opening-date'));
    await _scrollTo(tester, dateFinder);
    final formattedDate = MaterialLocalizations.of(
      tester.element(dateFinder),
    ).formatMediumDate(DateTime(2026, 7, 29));
    expect(
      tester.getSemantics(dateFinder),
      matchesSemantics(
        label: 'Дата начального остатка, $formattedDate',
        textDirection: TextDirection.ltr,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await _scrollTo(tester, find.byKey(const Key('account-evaluate')));
    expect(
      tester.getSize(find.byKey(const Key('account-evaluate'))).height,
      greaterThanOrEqualTo(48),
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing account opens the structured manual operation form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpPage(
      tester,
      repository: _FakeFinanceRepository(_initializedSetup()),
      settings: const AppSettings(
        themeMode: ThemeMode.dark,
        accent: AppAccent.purple,
      ),
    );

    expect(find.byKey(const Key('operation-type')), findsOneWidget);
    expect(find.byKey(const Key('operation-amount')), findsOneWidget);
    expect(find.byKey(const Key('operation-merchant')), findsOneWidget);
    expect(find.byKey(const Key('operation-category')), findsOneWidget);
    expect(find.text('Основной счёт'), findsOneWidget);
    final context = tester.element(find.byKey(const Key('finance-entry-page')));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'operation before opening date names the localized bound and guidance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _FakeFinanceRepository(
        _initializedSetup(),
        operationEvaluation: (draft) => FinanceOperationRejected(
          draft: draft,
          issues: const [
            FinanceIssue(
              code: FinanceIssueCode.operationBeforeAccountBaseline,
              field: FinanceIssueField.occurredOn,
            ),
          ],
        ),
      );

      await _pumpPage(tester, repository: repository);
      final pageContext = tester.element(
        find.byKey(const Key('finance-entry-page')),
      );
      final localizedBound = MaterialLocalizations.of(
        pageContext,
      ).formatMediumDate(DateTime(2026, 7, 1));

      await tester.enterText(find.byKey(const Key('operation-amount')), '5');
      await _scrollTo(tester, find.byKey(const Key('operation-evaluate')));
      await tester.tap(find.byKey(const Key('operation-evaluate')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Учёт по счёту начинается $localizedBound. '
          'Операции раньше этой даты записать нельзя. '
          'Дату начала можно перенести назад в настройках счёта.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('2026-07-01'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'privacy masks opening balance input and account review semantics at 360 dp',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpPage(
        tester,
        repository: _FakeFinanceRepository(_emptySetup()),
        settings: const AppSettings(privacyMode: true),
      );
      await tester.enterText(
        find.byKey(const Key('account-name')),
        'Тестовый счёт',
      );
      await tester.enterText(
        find.byKey(const Key('opening-balance')),
        '2468.10',
      );

      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('opening-balance')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.obscureText, isTrue);
      expect(find.semantics.byLabel(RegExp('2468[,.]10')), findsNothing);
      expect(find.semantics.byValue(RegExp('2468[,.]10')), findsNothing);
      expect(find.semantics.byValue(RegExp('•+')), findsOne);

      await _scrollTo(tester, find.byKey(const Key('account-evaluate')));
      await tester.tap(find.byKey(const Key('account-evaluate')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('finance-confirm')), findsOneWidget);
      expect(find.textContaining('2468'), findsNothing);
      expect(find.text('•••••• €'), findsOneWidget);
      expect(find.semantics.byLabel(RegExp('2468[,.]10')), findsNothing);
      expect(find.semantics.byValue(RegExp('2468[,.]10')), findsNothing);
      expect(find.semantics.byLabel(RegExp('••••••')), findsOne);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'privacy masks input and review semantics while accepted write stays accepted',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
        (_, command) => OperationDeliveryAccepted(
          commit: _operationCommit(command),
          homeStatus: AcceptedWriteHomeConvergenceResult.projectionDelayed,
        ),
      );

      await _pumpPage(
        tester,
        repository: _FakeFinanceRepository(_initializedSetup()),
        settings: const AppSettings(privacyMode: true),
        operationDeliveryCoordinator: deliveryCoordinator,
      );

      await tester.enterText(
        find.byKey(const Key('operation-amount')),
        '1234.56',
      );
      expect(find.bySemanticsLabel(RegExp('1234[,.]56')), findsNothing);

      await _scrollTo(tester, find.byKey(const Key('operation-evaluate')));
      await tester.tap(find.byKey(const Key('operation-evaluate')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('finance-confirm')), findsOneWidget);
      expect(find.textContaining('1234'), findsNothing);
      expect(find.text('•••••• €'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('••••••')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('1234[,.]56')), findsNothing);

      await tester.tap(find.byKey(const Key('finance-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('operation-accepted')), findsOneWidget);
      expect(find.textContaining('Операция уже сохранена'), findsOneWidget);
      expect(deliveryCoordinator.calls, hasLength(1));
      expect(find.textContaining('1234'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'queued authentication state removes reviewed amount at 360 dp and 200%',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _FakeFinanceRepository(_initializedSetup());
      final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
        (_, _) => const OperationDeliveryQueued(
          code: OperationOutboxErrorCode.sessionChanged,
        ),
      );
      await _pumpPage(
        tester,
        repository: repository,
        operationDeliveryCoordinator: deliveryCoordinator,
      );

      await tester.enterText(
        find.byKey(const Key('operation-amount')),
        '9876.54',
      );
      await _scrollTo(tester, find.byKey(const Key('operation-evaluate')));
      await tester.tap(find.byKey(const Key('operation-evaluate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('finance-confirm')), findsOneWidget);
      expect(find.textContaining('9876'), findsOneWidget);

      await _scrollTo(tester, find.byKey(const Key('finance-confirm')));
      await tester.tap(find.byKey(const Key('finance-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('finance-confirm')), findsNothing);
      expect(find.byKey(const Key('operation-amount')), findsNothing);
      expect(find.textContaining('9876'), findsNothing);
      expect(find.byKey(const Key('operation-queued')), findsOneWidget);
      expect(find.text('Операция сохранена на устройстве'), findsOneWidget);
      expect(find.textContaining('повторный вход'), findsOneWidget);
      expect(deliveryCoordinator.calls, hasLength(1));

      await _scrollTo(tester, find.text('Добавить ещё одну'));
      await tester.tap(find.text('Добавить ещё одну'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('operation-amount')), findsOneWidget);
      expect(find.textContaining('9876'), findsNothing);
      expect(deliveryCoordinator.calls, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('storage failure keeps review and explains local durability', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
      (_, _) => const OperationDeliveryStorageFailure(
        OperationOutboxErrorCode.storageUnavailable,
      ),
    );
    await _pumpPage(
      tester,
      repository: _FakeFinanceRepository(_initializedSetup()),
      operationDeliveryCoordinator: deliveryCoordinator,
    );

    await _reviewAndConfirmOperation(tester, amount: '77.15');

    expect(find.byKey(const Key('finance-confirm')), findsOneWidget);
    expect(find.textContaining('77,15'), findsOneWidget);
    expect(
      find.textContaining('Не удалось надёжно сохранить подтверждение'),
      findsOneWidget,
    );
    expect(deliveryCoordinator.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('permanent delivery failure shows attention without retry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final deliveryCoordinator = _FakeOperationDeliveryCoordinator(
      (_, _) => const OperationDeliveryPermanentFailure(
        OperationOutboxErrorCode.securityBlocked,
      ),
    );
    await _pumpPage(
      tester,
      repository: _FakeFinanceRepository(_initializedSetup()),
      operationDeliveryCoordinator: deliveryCoordinator,
    );

    await _reviewAndConfirmOperation(tester, amount: '31.40');

    expect(
      find.byKey(const Key('operation-delivery-attention')),
      findsOneWidget,
    );
    expect(find.text('Операция требует проверки'), findsOneWidget);
    expect(find.textContaining('проверки безопасности'), findsOneWidget);
    expect(find.textContaining('31,40'), findsNothing);
    expect(find.text('Добавить ещё одну'), findsNothing);
    expect(deliveryCoordinator.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  // Several wallets, one currency each (ADR 0029). Without a picker a hryvnia
  // wallet could be opened and never recorded into.
  testWidgets('one wallet offers no choice', (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeFinanceRepository(_initializedSetup()),
    );

    expect(find.byKey(const Key('operation-wallet')), findsNothing);
  });

  testWidgets('choosing a wallet keeps the amount and changes the currency', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeFinanceRepository(_walletSetup()));

    expect(find.byKey(const Key('operation-wallet')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('operation-amount')), '250.00');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('operation-wallet')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Гривна · UAH').last);
    await tester.pumpAndSettle();

    // Switching wallets is choosing where the money moved, not starting again.
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('operation-amount')))
          .controller
          ?.text,
      '250.00',
    );
    expect(find.text('UAH'), findsWidgets);
  });

  // The wallet list describes the profile, not one form. Every rebuild of the
  // entry form used to drop it, which collapsed the picker to the wallet in
  // hand: after a refusal or a recorded operation there was no way back to
  // another wallet without leaving the screen.
  testWidgets('a refusal keeps the choice of wallet', (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeFinanceRepository(
        _walletSetup(),
        operationEvaluation: (draft) => FinanceOperationRejected(
          draft: draft,
          issues: const [
            FinanceIssue(
              code: FinanceIssueCode.futureOccurredDate,
              field: FinanceIssueField.occurredOn,
            ),
          ],
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('operation-amount')), '250.00');
    await _scrollTo(tester, find.byKey(const Key('operation-evaluate')));
    await tester.tap(find.byKey(const Key('operation-evaluate')));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const Key('operation-wallet')));
    expect(find.byKey(const Key('operation-wallet')), findsOneWidget);
  });

  testWidgets('a recorded operation keeps the choice of wallet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpPage(
      tester,
      repository: _FakeFinanceRepository(_walletSetup()),
      operationDeliveryCoordinator: _FakeOperationDeliveryCoordinator(
        (_, command) => OperationDeliveryAccepted(
          commit: _operationCommit(command),
          homeStatus: AcceptedWriteHomeConvergenceResult.projectionDelayed,
        ),
      ),
    );

    await _reviewAndConfirmOperation(tester, amount: '18.00');
    await _scrollTo(tester, find.text('Добавить ещё одну'));
    await tester.tap(find.text('Добавить ещё одну'));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const Key('operation-wallet')));
    expect(find.byKey(const Key('operation-wallet')), findsOneWidget);
  });

  testWidgets('editing a reviewed operation keeps the choice of wallet', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeFinanceRepository(_walletSetup()));

    await tester.enterText(find.byKey(const Key('operation-amount')), '18.00');
    await _scrollTo(tester, find.byKey(const Key('operation-evaluate')));
    await tester.tap(find.byKey(const Key('operation-evaluate')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('finance-edit')));
    await tester.tap(find.byKey(const Key('finance-edit')));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const Key('operation-wallet')));
    expect(find.byKey(const Key('operation-wallet')), findsOneWidget);
  });
}

FinanceAccountSetup _walletSetup() => FinanceAccountSetup(
  canonicalTimezone: 'Europe/Berlin',
  timezoneRevision: 1,
  accounts: [_account(), _hryvniaWallet()],
);

FinanceAccount _hryvniaWallet() => const FinanceAccount(
  accountId: '55555555-5555-4555-8555-555555555555',
  userId: '22222222-2222-4222-8222-222222222222',
  commandId: '66666666-6666-4666-8666-666666666666',
  name: 'Гривна',
  currency: 'UAH',
  openingBalance: '0',
  openingBalanceOn: '2026-07-01',
  openingTimezone: 'Europe/Berlin',
  isDefault: false,
  confirmedAt: '2026-07-01T08:00:00Z',
  createdAt: '2026-07-01T08:00:00Z',
);

Future<void> _pumpPage(
  WidgetTester tester, {
  required FinanceEntryRepositoryClient repository,
  AppSettings settings = const AppSettings(),
  HomeRepository? homeRepository,
  OperationDeliveryCoordinator? operationDeliveryCoordinator,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(settings),
        financeEntryRepositoryProvider.overrideWithValue(repository),
        financeEntryClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 7, 29, 10),
        ),
        financeCommandIdFactoryProvider.overrideWithValue(
          () => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        ),
        financeCaptureContextSourceProvider.overrideWithValue(
          _FixedFinanceCaptureContextSource(_captureContext()),
        ),
        homeRepositoryProvider.overrideWithValue(
          homeRepository ?? _ProjectionLagHomeRepository(),
        ),
        acceptedWriteHomeDelayProvider.overrideWithValue((_) async {}),
        if (operationDeliveryCoordinator != null)
          operationDeliveryCoordinatorProvider.overrideWithValue(
            operationDeliveryCoordinator,
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
        home: Scaffold(
          body: FinanceEntryPage(
            onBackHome: _ignore,
            onSignInRequested: _ignore,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _reviewAndConfirmOperation(
  WidgetTester tester, {
  required String amount,
}) async {
  await tester.enterText(find.byKey(const Key('operation-amount')), amount);
  await _scrollTo(tester, find.byKey(const Key('operation-evaluate')));
  await tester.tap(find.byKey(const Key('operation-evaluate')));
  await tester.pumpAndSettle();
  await _scrollTo(tester, find.byKey(const Key('finance-confirm')));
  await tester.tap(find.byKey(const Key('finance-confirm')));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('finance-entry-page')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
}

void _ignore() {}

FinanceEntrySuccess<T> _success<T>(T value) =>
    FinanceEntrySuccess(requestId: 'req_finance_widget', value: value);

FinanceCaptureContext _captureContext() {
  return FinanceCaptureContext.fromPlatformValue({
    'capturedAtUtc': '2026-07-29T10:00:00.000Z',
    'osTimezone': 'America/Los_Angeles',
    'osLocalDate': '2026-07-29',
    'canonicalTimezone': configuredHomeApiTimezone,
    'canonicalLocalDate': '2026-07-29',
  }, expectedCanonicalTimezone: configuredHomeApiTimezone);
}

FinanceAccountSetup _emptySetup() => FinanceAccountSetup(
  canonicalTimezone: null,
  timezoneRevision: 0,
  accounts: const [],
);

FinanceAccountSetup _initializedSetup() => FinanceAccountSetup(
  canonicalTimezone: 'Europe/Berlin',
  timezoneRevision: 1,
  accounts: [_account()],
);

FinanceAccount _account() => const FinanceAccount(
  accountId: '11111111-1111-4111-8111-111111111111',
  userId: '22222222-2222-4222-8222-222222222222',
  commandId: '33333333-3333-4333-8333-333333333333',
  name: 'Основной счёт',
  currency: 'EUR',
  openingBalance: '100.00',
  openingBalanceOn: '2026-07-01',
  openingTimezone: 'Europe/Berlin',
  isDefault: true,
  confirmedAt: '2026-07-01T08:00:00Z',
  createdAt: '2026-07-01T08:00:00Z',
);

FinanceOperationCommit _operationCommit(FinanceOperationCommitCommand command) {
  final draft = command.review.draft;
  return FinanceOperationCommit(
    idempotentReplay: false,
    operation: CommittedFinanceOperation(
      operationId: '44444444-4444-4444-8444-444444444444',
      userId: _account().userId,
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
      createdAt: command.confirmedAt,
    ),
  );
}

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

final class _FakeFinanceRepository implements FinanceEntryRepositoryClient {
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
  _FakeFinanceRepository(this.setup, {this.operationEvaluation});

  final FinanceAccountSetup setup;
  final FinanceOperationEvaluation Function(FinanceOperationDraft draft)?
  operationEvaluation;
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
    return _success(setup);
  }

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount(
    FinanceAccountDraft draft,
  ) async => _success(
    FinanceAccountNeedsConfirmation(
      draft: draft,
      draftHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
  );

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount(
    FinanceAccountCommitCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline(
    FinanceBaselineDraft draft,
  ) => throw StateError('Unexpected baseline evaluation.');

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline(
    FinanceBaselineCommitCommand command,
  ) => throw StateError('Unexpected baseline commit.');

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) async => _success(
    operationEvaluation?.call(draft) ??
        FinanceOperationNeedsConfirmation(
          draft: draft,
          draftHash:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
  );

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

final class _FixedFinanceCaptureContextSource
    implements FinanceCaptureContextSource {
  const _FixedFinanceCaptureContextSource(this.context);

  final FinanceCaptureContext context;

  @override
  Future<FinanceCaptureContext> capture({
    required String canonicalTimezone,
  }) async => context;
}

final class _ProjectionLagHomeRepository
    implements HomeRepository, HomeCacheInvalidator {
  var calls = 0;
  var invalidations = 0;

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    calls += 1;
    return HomeFailureResult(
      type: HomeFailureType.serviceUnavailable,
      requestId: 'req_projection_$calls',
    );
  }

  @override
  Future<void> invalidateHomeCache() async {
    invalidations += 1;
  }
}
