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
import 'package:mobile_finance_assistant/features/finance_entry/presentation/operation_history_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _firstId = '11111111-1111-4111-8111-111111111111';
const _renamedId = '22222222-2222-4222-8222-222222222222';

void main() {
  testWidgets('an empty history says so instead of showing a bare list', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository(pages: [_page([])]));

    expect(find.byKey(const Key('history-empty')), findsOneWidget);
    expect(find.byKey(const Key('history-list')), findsNothing);
  });

  testWidgets('operations are listed with their category and signed amount', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        pages: [
          _page([
            _item(operationId: _firstId, category: 'Продукты', amount: '42.00'),
            _item(
              operationId: _renamedId,
              type: FinanceOperationType.income,
              category: 'Зарплата',
              amount: '1500.00',
            ),
          ]),
        ],
      ),
    );

    expect(find.byKey(const Key('history-row-$_firstId')), findsOneWidget);
    expect(find.text('Продукты'), findsOneWidget);
    // An expense reads as negative and an income as positive, and the word
    // says which it is: never money by colour alone.
    expect(find.text('−42,00 €'), findsOneWidget);
    expect(find.text('+1 500,00 €'), findsOneWidget);
    expect(find.textContaining('Расход'), findsOneWidget);
    expect(find.textContaining('Доход'), findsOneWidget);
  });

  testWidgets('privacy mode masks every amount in the list', (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        pages: [
          _page([_item(operationId: _firstId, amount: '42.00')]),
        ],
      ),
      privacy: true,
    );

    expect(find.textContaining('42'), findsNothing);
    expect(find.text('•••••• €'), findsOneWidget);
  });

  testWidgets('the detail shows the written text only when it differs', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        pages: [
          _page([
            // Recorded as "Кофе", the category later renamed to "Кофе и чай".
            _item(
              operationId: _renamedId,
              category: 'Кофе и чай',
              categoryText: 'Кофе',
            ),
            _item(
              operationId: _firstId,
              category: 'Продукты',
              categoryText: 'Продукты',
            ),
          ]),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('history-row-$_renamedId')));
    await tester.pumpAndSettle();

    final detail = find.byKey(const Key('history-detail'));
    expect(detail, findsOneWidget);
    expect(
      find.byKey(const Key('history-detail-original-text')),
      findsOneWidget,
    );
    // Both are scoped to the sheet: the category name is also on the row
    // behind it, which is correct and not what this asserts.
    expect(
      find.descendant(of: detail, matching: find.text('Кофе')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('Кофе и чай')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-row-$_firstId')));
    await tester.pumpAndSettle();

    // Identical values would be noise, so the row is absent rather than
    // repeating the category back to the user.
    expect(find.byKey(const Key('history-detail-original-text')), findsNothing);
  });

  testWidgets('a second page is appended without losing the first', (
    tester,
  ) async {
    final repository = _FakeRepository(
      pages: [
        _page([_item(operationId: _firstId, category: 'Продукты')], next: 'c1'),
        _page([_item(operationId: _renamedId, category: 'Транспорт')]),
      ],
    );
    await _pumpPage(tester, repository: repository);

    expect(find.byKey(const Key('history-load-more')), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-load-more')));
    await tester.pumpAndSettle();

    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text('Транспорт'), findsOneWidget);
    // The cursor the server issued is what was sent back, not a page number.
    expect(repository.requestedCursors, [null, 'c1']);
    expect(find.byKey(const Key('history-load-more')), findsNothing);
  });

  testWidgets('a failed page keeps what was already read on screen', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        pages: [
          _page([
            _item(operationId: _firstId, category: 'Продукты'),
          ], next: 'c1'),
        ],
        failAfterFirstPage: true,
      ),
    );

    await tester.tap(find.byKey(const Key('history-load-more')));
    await tester.pumpAndSettle();

    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text('Не удалось загрузить продолжение'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('an unreadable history offers a retry', (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        pages: [],
        listFailure: FinanceEntryFailureKind.serviceUnavailable,
      ),
    );

    expect(find.byKey(const Key('history-failure')), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('the list fits 360 dp at 200 percent text scale', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpPage(
      tester,
      repository: _FakeRepository(
        pages: [
          _page([
            _item(operationId: _firstId, category: 'Кафе и рестораны'),
            _item(operationId: _renamedId, category: 'Связь и интернет'),
          ]),
        ],
      ),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeRepository repository,
  bool privacy = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeEntryRepositoryProvider.overrideWithValue(repository),
        initialAppSettingsProvider.overrideWithValue(
          AppSettings(privacyMode: privacy),
        ),
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
        home: OperationHistoryPage(onSignInRequested: () async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

OperationHistoryList _page(
  List<OperationHistoryItem> operations, {
  String? next,
}) => OperationHistoryList(operations: operations, nextCursor: next);

OperationHistoryItem _item({
  required String operationId,
  FinanceOperationType type = FinanceOperationType.expense,
  String amount = '42.00',
  String? category = 'Продукты',
  String? categoryText,
}) => OperationHistoryItem(
  operationId: operationId,
  type: type,
  amount: amount,
  currency: 'EUR',
  accountId: null,
  category: category,
  categoryId: category == null ? null : _firstId,
  categoryText: categoryText ?? category,
  merchant: null,
  occurredOn: '2026-08-12',
  occurredAt: null,
  source: FinanceOperationSource.manualText,
  createdAt: '2026-08-12T12:00:00Z',
);

class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository({
    required this.pages,
    this.listFailure,
    this.failAfterFirstPage = false,
  });

  final List<OperationHistoryList> pages;
  final FinanceEntryFailureKind? listFailure;
  final bool failAfterFirstPage;
  final List<String?> requestedCursors = [];

  @override
  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required int limit,
    String? cursor,
  }) async {
    requestedCursors.add(cursor);
    if (listFailure != null) {
      return FinanceEntryFailureResult<OperationHistoryList>(
        FinanceEntryFailure(kind: listFailure!, requestId: 'req_synthetic'),
      );
    }
    if (cursor != null && failAfterFirstPage) {
      return FinanceEntryFailureResult<OperationHistoryList>(
        FinanceEntryFailure(
          kind: FinanceEntryFailureKind.timeout,
          requestId: 'req_synthetic',
        ),
      );
    }
    final index = cursor == null ? 0 : 1;
    return FinanceEntrySuccess<OperationHistoryList>(
      requestId: 'req_synthetic',
      value: pages[index],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
