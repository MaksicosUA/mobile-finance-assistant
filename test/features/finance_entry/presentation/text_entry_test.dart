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
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/finance_entry_page.dart';
import 'package:mobile_finance_assistant/features/voice_entry/application/voice_entry_controller.dart';
import 'package:mobile_finance_assistant/features/voice_entry/application/waiting_phrases_controller.dart';
import 'package:mobile_finance_assistant/features/voice_entry/data/waiting_phrase_store.dart';
import 'package:mobile_finance_assistant/features/voice_entry/domain/waiting_phrase.dart';

import '../../voice_entry/waiting_phrases_test.dart'
    show MemoryWaitingPhraseStore;
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _groceriesId = '44444444-4444-4444-8444-444444444444';
const _giftOutId = '55555555-5555-4555-8555-555555555555';
const _giftInId = '66666666-6666-4666-8666-666666666666';
const _freelanceId = '77777777-7777-4777-8777-777777777777';

/// Entering an operation by writing a sentence (ADR 0022).
///
/// The sentence fills the form. It never records anything: the confirmation
/// below is still what writes the operation.
void main() {
  testWidgets('a sentence fills the form and does not record anything', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Потратил 12,50 на продукты вчера',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('operation-amount')))
          .controller
          ?.text,
      '12.50',
    );
    expect(find.textContaining('Продукты'), findsWidgets);
    // Nothing was evaluated or committed: reading a sentence is not a write.
    expect(repository.evaluated, 0);
    expect(repository.parsed, hasLength(1));
  });

  // ADR 0031: a sentence spoken on Home arrives already read, and records
  // nothing until the card is confirmed — exactly like a typed one.
  testWidgets('a spoken sentence arrives read, once, with no keyboard', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _pumpPage(
      tester,
      repository: repository,
      spoken: 'Потратил 12,50 на продукты вчера',
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('operation-sentence')))
          .controller
          ?.text,
      'Потратил 12,50 на продукты вчера',
    );
    expect(repository.parsed.single.text, 'Потратил 12,50 на продукты вчера');
    expect(_amountText(tester), '12.50');
    expect(repository.evaluated, 0);
    // The words are on the card already; a keyboard would only cover it.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('operation-sentence')))
          .focusNode
          ?.hasFocus,
      isFalse,
    );
    // Taken: nothing is left to be read again by a later form.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FinanceEntryPage)),
    );
    expect(container.read(spokenSentenceProvider), isNull);
  });

  testWidgets('the capture pair travels so the day is the user own', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Потратил 10 сегодня',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    // The phone is in Los Angeles and the account reports in Berlin; the
    // server resolves the day from these two, never from server wall clock.
    final call = repository.parsed.single;
    expect(call.capturedAt, '2026-07-29T10:00:00.000Z');
    expect(call.capturedTimezone, 'America/Los_Angeles');
  });

  testWidgets('a gap names the field the parser refused to guess', (
    tester,
  ) async {
    final repository = _FakeRepository(
      proposal: _proposal(
        amount: null,
        gaps: const [OperationParseGap.amountNotFound],
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Купил продукты',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('operation-sentence-result')), findsOneWidget);
    expect(find.textContaining('Сумму не нашёл'), findsOneWidget);
  });

  testWidgets('a missing amount does not erase what the user already typed', (
    tester,
  ) async {
    final repository = _FakeRepository(
      proposal: _proposal(
        amount: null,
        gaps: const [OperationParseGap.amountNotFound],
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(find.byKey(const Key('operation-amount')), '99.00');
    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Купил продукты',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('operation-amount')))
          .controller
          ?.text,
      '99.00',
    );
  });

  // Issue 0007: the parser read the currency and nothing looked at what it
  // said, so «250 долларов» filled 250 into a field labelled € and confirmed
  // €250. The amount is the field this product exists to get right.
  testWidgets('an amount in another currency is not typed into this account', (
    tester,
  ) async {
    final repository = _FakeRepository(
      proposal: _proposal(amount: '250.00', currency: 'USD'),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Потратил 250 долларов на подписки',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(_amountText(tester), isEmpty);
    // Named on both sides, so the refusal is actionable rather than mysterious.
    expect(find.textContaining('Сумма в USD, а счёт в EUR'), findsOneWidget);
  });

  testWidgets('a currency the parser could not name is not filled either', (
    tester,
  ) async {
    final repository = _FakeRepository(
      proposal: _proposal(
        amount: '500.00',
        gaps: const [OperationParseGap.currencyNotUnderstood],
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Потратил 500 ¥',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(_amountText(tester), isEmpty);
    expect(find.textContaining('Валюту не разобрал'), findsOneWidget);
  });

  testWidgets('the account own currency still fills the amount', (
    tester,
  ) async {
    final repository = _FakeRepository(
      proposal: _proposal(amount: '12.50', currency: 'EUR'),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Потратил 12,50 на продукты',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(_amountText(tester), '12.50');
    expect(find.textContaining('не подставил'), findsNothing);
  });

  testWidgets('a sentence is read for the wallet it is recorded into', (
    tester,
  ) async {
    // «кава 50» on a hryvnia wallet names no currency, and euro is not what it
    // means there (issue 0013).
    final repository = _FakeRepository(
      walletCurrency: 'UAH',
      proposal: _proposal(amount: '50', currency: 'UAH'),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'кава 50',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(repository.parsed.single.accountCurrency, 'UAH');
    expect(_amountText(tester), '50');
    expect(find.textContaining('не подставил'), findsNothing);
  });

  testWidgets('a refused currency still leaves the date and category read', (
    tester,
  ) async {
    // Only the amount is in the wrong unit. Throwing away what was read
    // correctly would make the refusal cost more than it saves.
    final repository = _FakeRepository(
      proposal: _proposal(amount: '250.00', currency: 'USD'),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Потратил 250 долларов на продукты вчера',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Продукты'), findsWidgets);
  });

  testWidgets('a failed parse says so and leaves the form usable', (
    tester,
  ) async {
    final repository = _FakeRepository(
      failure: FinanceEntryFailureKind.serviceUnavailable,
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Потратил 12 на продукты',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('operation-sentence-error')), findsOneWidget);
    // The structured form is untouched, so a broken parser never blocks
    // recording money.
    expect(find.byKey(const Key('operation-amount')), findsOneWidget);
    expect(find.byKey(const Key('operation-evaluate')), findsOneWidget);
  });

  testWidgets('opened from Home, the keyboard lands on the sentence', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository(), focusSentence: true);

    // Home's entry action exists to make recording one line quick, so the
    // field that reads a line is the one that has focus.
    final field = tester.widget<TextField>(
      find.byKey(const Key('operation-sentence')),
    );
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('opened as a tab, nothing steals the keyboard', (tester) async {
    await _pumpPage(tester, repository: _FakeRepository());

    final field = tester.widget<TextField>(
      find.byKey(const Key('operation-sentence')),
    );
    expect(field.focusNode?.hasFocus, isFalse);
  });

  testWidgets('an empty sentence is refused without a request', (tester) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(repository.parsed, isEmpty);
    expect(find.byKey(const Key('operation-sentence-error')), findsOneWidget);
  });
  testWidgets('a sentence that flips direction does not crash the picker', (
    tester,
  ) async {
    // The category chosen while this was an expense is not offered once the
    // entry becomes income, and a dropdown asserts when its value is missing
    // from its own items. It reached a device as a red screen.
    final repository = _FakeRepository(
      proposals: [
        _proposal(),
        OperationProposal(
          type: FinanceOperationType.income,
          amount: '50',
          currency: 'EUR',
          occurredOn: '2026-07-28',
          sourceExpression: 'вчера',
          categoryId: null,
          category: null,
          gaps: const [OperationParseGap.categoryNotMatched],
        ),
      ],
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'потратил 12,50 на продукты',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'получил доход от крипты вчера 50',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('operation-category-picker')), findsOneWidget);
  });

  testWidgets('a sentence about an exchange fills nothing and offers transfer', (
    tester,
  ) async {
    // Issue 0009: «Перевёл 100 евро получил 5200 гривен» was recorded as
    // income of 100 EUR. The form must stay empty and point at the screen that
    // can actually record it.
    final repository = _FakeRepository(
      proposal: const OperationProposal(
        type: FinanceOperationType.expense,
        amount: null,
        currency: 'EUR',
        occurredOn: '2026-07-29',
        sourceExpression: null,
        categoryId: null,
        category: null,
        gaps: [OperationParseGap.transferNotAnOperation],
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Перевёл 100 евро получил 5200 гривен',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(_amountText(tester), '');
    expect(_pickedCategory(tester), isNull);
    expect(find.textContaining('перевод между кошельками'), findsOneWidget);
    expect(
      find.byKey(const Key('operation-sentence-open-transfer')),
      findsOneWidget,
    );
    // Nothing was recorded by reading a sentence, as always.
    expect(repository.evaluated, 0);
  });

  testWidgets('an ordinary sentence offers no transfer', (tester) async {
    await _pumpPage(tester, repository: _FakeRepository());

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'потратил 12,50 на продукты',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('operation-sentence-open-transfer')),
      findsNothing,
    );
  });

  testWidgets(
    'a sentence that matches nothing withdraws what a sentence filled',
    (tester) async {
      // Issue 0011: the category stayed from the previous sentence, so the card
      // went on asserting «Продукты» for a tank of fuel. What a parse filled is
      // the parse's to withdraw.
      final repository = _FakeRepository(
        proposals: [_proposal(), _unmatchedProposal()],
      );
      await _pumpPage(tester, repository: repository);

      await tester.enterText(
        find.byKey(const Key('operation-sentence')),
        'потратил 12,50 на продукты',
      );
      await tester.tap(find.byKey(const Key('operation-sentence-parse')));
      await tester.pumpAndSettle();
      expect(_pickedCategory(tester), _groceriesId);

      await tester.enterText(
        find.byKey(const Key('operation-sentence')),
        'потратил 40 на заправку',
      );
      await tester.tap(find.byKey(const Key('operation-sentence-parse')));
      await tester.pumpAndSettle();

      expect(_pickedCategory(tester), isNull);
      // The amount is still the parser's to fill: only the category was withdrawn.
      expect(_amountText(tester), '40.00');
    },
  );

  testWidgets(
    'a category chosen by hand survives a sentence that matches nothing',
    (tester) async {
      // The mirror of the rule above, and the reason it is not "clear on every
      // gap": a deliberate choice is not the parser's to undo.
      final repository = _FakeRepository(proposals: [_unmatchedProposal()]);
      await _pumpPage(tester, repository: repository);

      await tester.tap(find.byKey(const Key('operation-category-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продукты').last);
      await tester.pumpAndSettle();
      expect(_pickedCategory(tester), _groceriesId);

      await tester.enterText(
        find.byKey(const Key('operation-sentence')),
        'потратил 40 на заправку',
      );
      await tester.tap(find.byKey(const Key('operation-sentence-parse')));
      await tester.pumpAndSettle();

      expect(_pickedCategory(tester), _groceriesId);
    },
  );

  group('which way the money went', () {
    Future<void> read(WidgetTester tester, String sentence) async {
      await tester.enterText(
        find.byKey(const Key('operation-sentence')),
        sentence,
      );
      await tester.tap(find.byKey(const Key('operation-sentence-parse')));
      await tester.pumpAndSettle();
    }

    Set<FinanceOperationType> selectedDirection(WidgetTester tester) => tester
        .widget<SegmentedButton<FinanceOperationType>>(
          find.byKey(const Key('operation-type')),
        )
        .selected;

    testWidgets('a sentence that does not say is asked about, nothing chosen', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        repository: _FakeRepository(proposal: _unclearGift()),
      );

      await read(tester, 'подарок 5000');

      expect(find.byKey(const Key('operation-direction-expense')), findsOne);
      expect(find.byKey(const Key('operation-direction-income')), findsOne);
      expect(find.textContaining('расход это или доход'), findsOneWidget);
      // Defaulting here is how a gift arrived as spending.
      expect(selectedDirection(tester), isEmpty);
    });

    testWidgets('one tap on income brings the income category with it', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        repository: _FakeRepository(proposal: _unclearGift()),
      );
      await read(tester, 'подарок 5000');
      expect(_pickedCategory(tester), _giftOutId);

      await tester.tap(find.byKey(const Key('operation-direction-income')));
      await tester.pumpAndSettle();

      expect(selectedDirection(tester), {FinanceOperationType.income});
      expect(_pickedCategory(tester), _giftInId);
      expect(find.byKey(const Key('operation-direction-income')), findsNothing);
      expect(find.textContaining('расход это или доход'), findsNothing);
    });

    testWidgets('one tap on expense keeps what was filled', (tester) async {
      await _pumpPage(
        tester,
        repository: _FakeRepository(proposal: _unclearGift()),
      );
      await read(tester, 'подарок 5000');

      await tester.tap(find.byKey(const Key('operation-direction-expense')));
      await tester.pumpAndSettle();

      expect(selectedDirection(tester), {FinanceOperationType.expense});
      expect(_pickedCategory(tester), _giftOutId);
      expect(
        find.byKey(const Key('operation-direction-expense')),
        findsNothing,
      );
    });

    testWidgets('the switch itself answers the question', (tester) async {
      await _pumpPage(
        tester,
        repository: _FakeRepository(proposal: _unclearGift()),
      );
      await read(tester, 'подарок 5000');

      await tester.tap(find.text('Доход').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('operation-direction-income')), findsNothing);
      expect(_pickedCategory(tester), _giftInId);
    });

    testWidgets('the form does not go on until the question is answered', (
      tester,
    ) async {
      final repository = _FakeRepository(proposal: _unclearGift());
      await _pumpPage(tester, repository: repository);
      await read(tester, 'подарок 5000');

      await tester.tap(find.byKey(const Key('operation-evaluate')));
      await tester.pumpAndSettle();
      expect(repository.evaluated, 0);
      expect(find.byKey(const Key('operation-direction-income')), findsOne);

      await tester.tap(find.byKey(const Key('operation-direction-income')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('operation-evaluate')));
      await tester.pumpAndSettle();

      expect(repository.evaluated, 1);
      expect(repository.draft?.type, FinanceOperationType.income);
      expect(repository.draft?.categoryId, _giftInId);
    });

    testWidgets('going on scrolls back to a question left out of sight', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        repository: _FakeRepository(proposal: _unclearGift()),
        size: const Size(390, 500),
      );
      await read(tester, 'подарок 5000');
      await tester.ensureVisible(find.byKey(const Key('operation-evaluate')));
      await tester.pumpAndSettle();
      final out = tester.getTopLeft(
        find.byKey(const Key('operation-direction-income')),
      );
      expect(out.dy, lessThan(0));

      await tester.tap(find.byKey(const Key('operation-evaluate')));
      await tester.pumpAndSettle();

      expect(
        tester
            .getTopLeft(find.byKey(const Key('operation-direction-income')))
            .dy,
        inInclusiveRange(0, 500),
      );
    });

    testWidgets('a category only income knows arrives with the answer', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        repository: _FakeRepository(
          proposal: const OperationProposal(
            type: FinanceOperationType.expense,
            amount: '500',
            currency: 'EUR',
            occurredOn: '2026-07-29',
            sourceExpression: null,
            categoryId: null,
            category: null,
            otherCategoryId: _freelanceId,
            gaps: [
              OperationParseGap.categoryNotMatched,
              OperationParseGap.directionNotClear,
            ],
          ),
        ),
      );
      await read(tester, 'фриланс 500');
      // Missing is not yet true: the words may lead to the other side.
      expect(find.textContaining('Категорию не подобрал'), findsNothing);

      await tester.tap(find.byKey(const Key('operation-direction-income')));
      await tester.pumpAndSettle();

      expect(_pickedCategory(tester), _freelanceId);
    });

    testWidgets('correcting a stated direction brings the category too', (
      tester,
    ) async {
      // The complaint itself: the card said expense, and switching it to income
      // left «Без категории» to choose all over again.
      await _pumpPage(
        tester,
        repository: _FakeRepository(
          proposal: const OperationProposal(
            type: FinanceOperationType.expense,
            amount: '5000',
            currency: 'EUR',
            occurredOn: '2026-07-29',
            sourceExpression: null,
            categoryId: _giftOutId,
            category: 'подарил',
            otherCategoryId: _giftInId,
          ),
        ),
      );
      await read(tester, 'подарил 5000');
      expect(find.byKey(const Key('operation-direction-income')), findsNothing);

      await tester.tap(find.text('Доход').last);
      await tester.pumpAndSettle();
      expect(_pickedCategory(tester), _giftInId);

      await tester.tap(find.text('Расход').last);
      await tester.pumpAndSettle();
      expect(_pickedCategory(tester), _giftOutId);
    });

    testWidgets('a switch with nothing to bring leaves the category empty', (
      tester,
    ) async {
      await _pumpPage(tester, repository: _FakeRepository());
      await read(tester, 'потратил 12,50 на продукты');

      await tester.tap(find.text('Доход').last);
      await tester.pumpAndSettle();

      expect(_pickedCategory(tester), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a clearer sentence takes the question back', (tester) async {
      await _pumpPage(
        tester,
        repository: _FakeRepository(proposals: [_unclearGift(), _proposal()]),
      );
      await read(tester, 'подарок 5000');
      await read(tester, 'купил продукты 12,50');

      expect(find.byKey(const Key('operation-direction-income')), findsNothing);
      expect(selectedDirection(tester), {FinanceOperationType.expense});
    });

    for (final language in const ['ru', 'uk', 'en', 'de']) {
      testWidgets('the question fits at 200% in $language', (tester) async {
        await _pumpPage(
          tester,
          repository: _FakeRepository(proposal: _unclearGift()),
          size: const Size(360, 3000),
          locale: Locale(language),
          textScale: 2,
        );
        await read(tester, 'подарок 5000');

        expect(tester.takeException(), isNull);
        final button = tester.getSize(
          find.byKey(const Key('operation-direction-income')),
        );
        expect(button.height, greaterThanOrEqualTo(48));
      });
    }
  });

  group('phrases said without a connection (ADR 0032)', () {
    testWidgets('a waiting phrase is read as of when it was said, then goes', (
      tester,
    ) async {
      final waiting = MemoryWaitingPhraseStore(initial: [_waitingPhrase()]);
      final repository = _FakeRepository();
      await _pumpPage(tester, repository: repository, waiting: waiting);

      expect(find.byKey(const Key('waiting-phrases')), findsOneWidget);
      expect(find.text('Вчера заплатил 80 за свет'), findsOneWidget);
      expect(repository.parsed, isEmpty, reason: 'nothing read unasked');

      await tester.tap(find.text('Вчера заплатил 80 за свет'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('operation-sentence')))
            .controller
            ?.text,
        'Вчера заплатил 80 за свет',
      );
      // Said on the 26th; the form is open on the 29th.
      expect(repository.parsed.single.capturedAt, '2026-07-26T18:30:00.000Z');
      expect(repository.parsed.single.capturedTimezone, 'Europe/Kyiv');
      expect(find.textContaining('Сказано 26 июля'), findsOneWidget);
      // Read, so it no longer waits — on the phone or in the list.
      expect(waiting.phrases, isEmpty);
      expect(find.byKey(const Key('waiting-phrases')), findsNothing);
      // And still nothing is recorded until the card is confirmed.
      expect(repository.evaluated, 0);
    });

    testWidgets('reading it again after a correction keeps when it was said', (
      tester,
    ) async {
      final repository = _FakeRepository();
      await _pumpPage(
        tester,
        repository: repository,
        waiting: MemoryWaitingPhraseStore(initial: [_waitingPhrase()]),
      );
      await tester.tap(find.text('Вчера заплатил 80 за свет'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('operation-sentence')),
        'Вчера заплатил 85 за свет',
      );
      await tester.tap(find.byKey(const Key('operation-sentence-parse')));
      await tester.pumpAndSettle();

      expect(repository.parsed.last.capturedAt, '2026-07-26T18:30:00.000Z');

      // Emptied and rewritten: a new sentence, said now.
      await tester.enterText(find.byKey(const Key('operation-sentence')), '');
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('operation-sentence')),
        'Потратил 10 сегодня',
      );
      await tester.tap(find.byKey(const Key('operation-sentence-parse')));
      await tester.pumpAndSettle();

      expect(repository.parsed.last.capturedAt, '2026-07-29T10:00:00.000Z');
      expect(find.textContaining('Сказано'), findsNothing);
    });

    testWidgets('a phrase that could not be read stays waiting', (
      tester,
    ) async {
      final waiting = MemoryWaitingPhraseStore(initial: [_waitingPhrase()]);
      await _pumpPage(
        tester,
        repository: _FakeRepository(failure: FinanceEntryFailureKind.offline),
        waiting: waiting,
      );

      await tester.tap(find.text('Вчера заплатил 80 за свет'));
      await tester.pumpAndSettle();

      expect(waiting.phrases, hasLength(1));
      expect(find.byKey(const Key('operation-sentence-error')), findsOneWidget);
    });

    testWidgets('privacy mode hides the words, not the phrase', (tester) async {
      await _pumpPage(
        tester,
        repository: _FakeRepository(),
        waiting: MemoryWaitingPhraseStore(initial: [_waitingPhrase()]),
        privacy: true,
      );

      expect(find.byKey(const Key('waiting-phrases')), findsOneWidget);
      expect(find.text('Вчера заплатил 80 за свет'), findsNothing);
      expect(find.text('Фраза скрыта'), findsOneWidget);
    });

    testWidgets('a phrase can be deleted unread', (tester) async {
      final waiting = MemoryWaitingPhraseStore(initial: [_waitingPhrase()]);
      final repository = _FakeRepository();
      await _pumpPage(tester, repository: repository, waiting: waiting);

      await tester.tap(
        find.byKey(Key('waiting-phrase-forget-${_waitingPhrase().id}')),
      );
      await tester.pumpAndSettle();

      expect(waiting.phrases, isEmpty);
      expect(repository.parsed, isEmpty);
      expect(find.byKey(const Key('waiting-phrases')), findsNothing);
    });

    testWidgets('a spoken phrase is read as of when it was said', (
      tester,
    ) async {
      final phrase = _waitingPhrase();
      final waiting = MemoryWaitingPhraseStore(initial: [phrase]);
      final repository = _FakeRepository();
      await _pumpPage(
        tester,
        repository: repository,
        waiting: waiting,
        heard: HeardSentence(phrase.text, kept: phrase),
      );

      expect(repository.parsed.single.capturedAt, '2026-07-26T18:30:00.000Z');
      expect(waiting.phrases, isEmpty);
      // The one in the field is not offered a second time above it.
      expect(find.byKey(const Key('waiting-phrases')), findsNothing);
    });

    testWidgets('offline, the screen says the spoken words are safe', (
      tester,
    ) async {
      final phrase = _waitingPhrase();
      await _pumpPage(
        tester,
        repository: _FakeRepository(
          accountsFailure: FinanceEntryFailureKind.offline,
        ),
        waiting: MemoryWaitingPhraseStore(initial: [phrase]),
        heard: HeardSentence(phrase.text, kept: phrase),
      );

      expect(find.byKey(const Key('spoken-sentence-kept')), findsOneWidget);
      expect(find.textContaining('до 30 дней'), findsOneWidget);
    });

    testWidgets('offline, words that could not be kept are said to be lost', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        repository: _FakeRepository(
          accountsFailure: FinanceEntryFailureKind.offline,
        ),
        heard: const HeardSentence('Вчера заплатил 80 за свет'),
      );

      expect(find.byKey(const Key('spoken-sentence-not-kept')), findsOneWidget);
      expect(find.byKey(const Key('spoken-sentence-kept')), findsNothing);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeRepository repository,
  bool focusSentence = false,
  String? spoken,
  HeardSentence? heard,
  MemoryWaitingPhraseStore? waiting,
  bool privacy = false,
  Size size = const Size(390, 1800),
  Locale locale = const Locale('ru'),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(
          AppSettings(privacyMode: privacy),
        ),
        financeEntryRepositoryProvider.overrideWithValue(repository),
        waitingPhraseStoreProvider.overrideWithValue(
          waiting ?? MemoryWaitingPhraseStore(),
        ),
        waitingPhraseScopeProvider.overrideWithValue(() async => 'scope-a'),
        waitingPhraseClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 7, 29, 10),
        ),
        financeEntryClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 7, 29, 10),
        ),
        financeCaptureContextSourceProvider.overrideWithValue(
          const _FixedCapture(),
        ),
        if (heard ?? (spoken == null ? null : HeardSentence(spoken))
            case final sentence?)
          spokenSentenceProvider.overrideWith(() => _Spoken(sentence)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(AppAccent.teal),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: FinanceEntryPage(
            onBackHome: _ignore,
            onSignInRequested: _ignore,
            focusSentence: focusSentence,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// What the picker currently holds, as the dropdown itself reports it.
String? _pickedCategory(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<String?>>(
      find.byKey(const Key('operation-category-picker')),
    )
    .initialValue;

String _amountText(WidgetTester tester) =>
    tester
        .widget<TextFormField>(find.byKey(const Key('operation-amount')))
        .controller
        ?.text ??
    '';

void _ignore() {}

WaitingPhrase _waitingPhrase() => WaitingPhrase(
  id: '00000000-0000-4000-8000-000000000001',
  text: 'Вчера заплатил 80 за свет',
  saidAt: DateTime.utc(2026, 7, 26, 18, 30),
  saidInTimezone: 'Europe/Kyiv',
);

/// A sentence the recogniser handed over on Home before the form opened.
class _Spoken extends SpokenSentence {
  _Spoken(this._sentence);

  final HeardSentence _sentence;

  @override
  HeardSentence? build() => _sentence;
}

OperationProposal _proposal({
  String? amount = '12.50',
  String currency = 'EUR',
  List<OperationParseGap> gaps = const [],
}) {
  return OperationProposal(
    type: FinanceOperationType.expense,
    amount: amount,
    currency: currency,
    occurredOn: '2026-07-28',
    sourceExpression: 'вчера',
    categoryId: _groceriesId,
    category: 'продукты',
    gaps: gaps,
  );
}

/// A sentence the parser read, except for the category: the same direction, so
/// nothing but the gap can explain what the picker does next.
OperationProposal _unmatchedProposal() => const OperationProposal(
  type: FinanceOperationType.expense,
  amount: '40.00',
  currency: 'EUR',
  occurredOn: '2026-07-28',
  sourceExpression: 'вчера',
  categoryId: null,
  category: null,
  gaps: [OperationParseGap.categoryNotMatched],
);

/// «подарок 5000»: both directions have the word and nothing says which.
OperationProposal _unclearGift() => const OperationProposal(
  type: FinanceOperationType.expense,
  amount: '5000',
  currency: 'EUR',
  occurredOn: '2026-07-29',
  sourceExpression: null,
  categoryId: _giftOutId,
  category: 'подарок',
  otherCategoryId: _giftInId,
  gaps: [OperationParseGap.directionNotClear],
);

final class _FixedCapture implements FinanceCaptureContextSource {
  const _FixedCapture();

  @override
  Future<FinanceCaptureContext> capture({
    required String canonicalTimezone,
  }) async => FinanceCaptureContext.fromPlatformValue({
    'capturedAtUtc': '2026-07-29T10:00:00.000Z',
    'osTimezone': 'America/Los_Angeles',
    'osLocalDate': '2026-07-29',
    'canonicalTimezone': configuredHomeApiTimezone,
    'canonicalLocalDate': '2026-07-29',
  }, expectedCanonicalTimezone: configuredHomeApiTimezone);
}

class _FakeRepository implements FinanceEntryRepositoryClient {
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

  _FakeRepository({
    OperationProposal? proposal,
    List<OperationProposal>? proposals,
    this.failure,
    this.accountsFailure,
    this.walletCurrency = 'EUR',
  }) : proposal = proposal ?? _proposal(),
       _queued = List<OperationProposal>.of(proposals ?? const []);

  final OperationProposal proposal;
  final List<OperationProposal> _queued;
  final FinanceEntryFailureKind? failure;

  /// Why the account cannot be read, when it cannot — offline, say.
  final FinanceEntryFailureKind? accountsFailure;
  final String walletCurrency;
  final List<
    ({
      String text,
      String capturedAt,
      String capturedTimezone,
      String accountCurrency,
    })
  >
  parsed = [];
  int evaluated = 0;
  FinanceOperationDraft? draft;

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    if (accountsFailure case final kind?) {
      return FinanceEntryFailureResult<FinanceAccountSetup>(
        FinanceEntryFailure(kind: kind, requestId: 'req_synthetic'),
      );
    }
    return FinanceEntrySuccess<FinanceAccountSetup>(
      requestId: 'req_synthetic',
      value: FinanceAccountSetup(
        canonicalTimezone: 'Europe/Berlin',
        timezoneRevision: 1,
        accounts: [
          FinanceAccount(
            accountId: '11111111-1111-4111-8111-111111111111',
            userId: '22222222-2222-4222-8222-222222222222',
            commandId: '33333333-3333-4333-8333-333333333333',
            name: 'Основной счёт',
            currency: walletCurrency,
            openingBalance: '100.00',
            openingBalanceOn: '2026-07-01',
            openingTimezone: 'Europe/Berlin',
            isDefault: true,
            confirmedAt: '2026-07-01T08:00:00Z',
            createdAt: '2026-07-01T08:00:00Z',
          ),
        ],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceCategoryList>> listCategories() async {
    return FinanceEntrySuccess<FinanceCategoryList>(
      requestId: 'req_synthetic',
      value: FinanceCategoryList(
        categories: [
          const FinanceCategory(
            categoryId: _groceriesId,
            name: 'Продукты',
            direction: FinanceOperationType.expense,
            systemKey: null,
          ),
          const FinanceCategory(
            categoryId: _giftOutId,
            name: 'Подарки',
            direction: FinanceOperationType.expense,
            systemKey: 'gifts_out',
          ),
          const FinanceCategory(
            categoryId: _giftInId,
            name: 'Подарки',
            direction: FinanceOperationType.income,
            systemKey: 'gifts_in',
          ),
          const FinanceCategory(
            categoryId: _freelanceId,
            name: 'Подработка',
            direction: FinanceOperationType.income,
            systemKey: 'freelance',
          ),
        ],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<OperationProposal>> parseOperationText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
    required String accountCurrency,
  }) async {
    parsed.add((
      text: text,
      capturedAt: capturedAt,
      capturedTimezone: capturedTimezone,
      accountCurrency: accountCurrency,
    ));
    final kind = failure;
    if (kind != null) {
      return FinanceEntryFailureResult<OperationProposal>(
        FinanceEntryFailure(kind: kind, requestId: 'req_synthetic'),
      );
    }
    return FinanceEntrySuccess<OperationProposal>(
      requestId: 'req_synthetic',
      value: _queued.isEmpty ? proposal : _queued.removeAt(0),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) async {
    evaluated += 1;
    this.draft = draft;
    return FinanceEntryFailureResult<FinanceOperationEvaluation>(
      FinanceEntryFailure(
        kind: FinanceEntryFailureKind.unknown,
        requestId: 'req_synthetic',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
