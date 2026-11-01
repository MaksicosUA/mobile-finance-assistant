import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/core/platform/finance_capture_context.dart';
import 'package:mobile_finance_assistant/core/platform/speech_input.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/text_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/voice_entry/application/voice_entry_controller.dart';
import 'package:mobile_finance_assistant/features/voice_entry/application/waiting_phrases_controller.dart';
import 'package:mobile_finance_assistant/features/voice_entry/data/waiting_phrase_store.dart';
import 'package:mobile_finance_assistant/features/voice_entry/domain/waiting_phrase.dart';

/// A phrase said without a connection waits until the server has read it
/// (ADR 0032).
void main() {
  group('speaking', () {
    test('keeps the words with the moment they were said', () async {
      final store = MemoryWaitingPhraseStore();
      final container = _container(store: store);
      addTearDown(container.dispose);

      final outcome = await container
          .read(voiceEntryControllerProvider.notifier)
          .listen(prompt: 'prompt');

      expect(outcome, VoiceEntryOutcome.heard);
      final heard = container.read(spokenSentenceProvider)!;
      expect(heard.text, 'Купил кофе за три пятьдесят');
      expect(heard.kept, isNotNull);
      expect(heard.kept!.saidAt, DateTime.utc(2026, 10, 29, 10));
      expect(heard.kept!.saidInTimezone, 'Europe/Kyiv');
      expect(store.phrases.single.id, heard.kept!.id);
      expect(container.read(waitingPhrasesProvider).single.id, heard.kept!.id);
    });

    test('with nobody signed in still hands the words over', () async {
      final store = MemoryWaitingPhraseStore();
      final container = _container(store: store, scope: null);
      addTearDown(container.dispose);

      final outcome = await container
          .read(voiceEntryControllerProvider.notifier)
          .listen(prompt: 'prompt');

      expect(outcome, VoiceEntryOutcome.heard);
      expect(container.read(spokenSentenceProvider)!.kept, isNull);
      expect(store.phrases, isEmpty);
    });

    test('a full store does not stop speaking', () async {
      final store = MemoryWaitingPhraseStore(full: true);
      final container = _container(store: store);
      addTearDown(container.dispose);

      await container
          .read(voiceEntryControllerProvider.notifier)
          .listen(prompt: 'prompt');

      final heard = container.read(spokenSentenceProvider)!;
      expect(heard.text, 'Купил кофе за три пятьдесят');
      expect(heard.kept, isNull);
    });
  });

  group('reading a waiting phrase', () {
    test('asks as of when it was said, not now', () async {
      final phrase = _phrase();
      final store = MemoryWaitingPhraseStore(initial: [phrase]);
      final repository = _ParseRepository.answering();
      final container = _container(store: store, repository: repository);
      addTearDown(container.dispose);
      final keepAlive = container.listen(
        textEntryControllerProvider,
        (_, _) {},
      );
      addTearDown(keepAlive.close);

      await container
          .read(textEntryControllerProvider.notifier)
          .parse(phrase.text, accountCurrency: 'EUR', phrase: phrase);
      await pumpEventQueue();

      // Said on the 26th in Kyiv; read on the 29th. «вчера» is the 25th.
      expect(repository.calls.single.capturedAt, '2026-10-26T18:30:00.000Z');
      expect(repository.calls.single.capturedTimezone, 'Europe/Kyiv');
      expect(store.phrases, isEmpty, reason: 'read, so it no longer waits');
      expect(container.read(waitingPhrasesProvider), isEmpty);
    });

    for (final kind in [
      FinanceEntryFailureKind.offline,
      FinanceEntryFailureKind.timeout,
      FinanceEntryFailureKind.serviceUnavailable,
      FinanceEntryFailureKind.unauthorized,
    ]) {
      test('$kind leaves it waiting', () async {
        final phrase = _phrase();
        final store = MemoryWaitingPhraseStore(initial: [phrase]);
        final container = _container(
          store: store,
          repository: _ParseRepository.failing(kind),
        );
        addTearDown(container.dispose);
        final keepAlive = container.listen(
          textEntryControllerProvider,
          (_, _) {},
        );
        addTearDown(keepAlive.close);

        await container
            .read(textEntryControllerProvider.notifier)
            .parse(phrase.text, accountCurrency: 'EUR', phrase: phrase);
        await pumpEventQueue();

        expect(store.phrases.single.id, phrase.id);
      });
    }

    test('a refusal no retry would change lets it go', () async {
      final phrase = _phrase();
      final store = MemoryWaitingPhraseStore(initial: [phrase]);
      final container = _container(
        store: store,
        repository: _ParseRepository.failing(FinanceEntryFailureKind.rejected),
      );
      addTearDown(container.dispose);
      final keepAlive = container.listen(
        textEntryControllerProvider,
        (_, _) {},
      );
      addTearDown(keepAlive.close);

      await container
          .read(textEntryControllerProvider.notifier)
          .parse(phrase.text, accountCurrency: 'EUR', phrase: phrase);
      await pumpEventQueue();

      expect(store.phrases, isEmpty);
    });

    test('a typed sentence is read as of now and touches nothing', () async {
      final phrase = _phrase();
      final store = MemoryWaitingPhraseStore(initial: [phrase]);
      final repository = _ParseRepository.answering();
      final container = _container(store: store, repository: repository);
      addTearDown(container.dispose);
      final keepAlive = container.listen(
        textEntryControllerProvider,
        (_, _) {},
      );
      addTearDown(keepAlive.close);

      await container
          .read(textEntryControllerProvider.notifier)
          .parse('Потратил 10 сегодня', accountCurrency: 'EUR');
      await pumpEventQueue();

      expect(repository.calls.single.capturedAt, '2026-10-29T10:00:00.000Z');
      expect(store.phrases.single.id, phrase.id);
    });
  });

  test('the list loads for the signed-in account', () async {
    final store = MemoryWaitingPhraseStore(initial: [_phrase()]);
    final container = _container(store: store);
    addTearDown(container.dispose);

    expect(container.read(waitingPhrasesProvider), isEmpty);
    await pumpEventQueue();

    expect(container.read(waitingPhrasesProvider), hasLength(1));
    expect(store.scopes, everyElement('scope-a'));
  });
}

WaitingPhrase _phrase() => WaitingPhrase(
  id: '00000000-0000-4000-8000-000000000001',
  text: 'Вчера заплатил 80 за свет',
  saidAt: DateTime.utc(2026, 10, 26, 18, 30),
  saidInTimezone: 'Europe/Kyiv',
);

ProviderContainer _container({
  required MemoryWaitingPhraseStore store,
  String? scope = 'scope-a',
  FinanceEntryRepositoryClient? repository,
}) {
  return ProviderContainer(
    overrides: [
      waitingPhraseStoreProvider.overrideWithValue(store),
      waitingPhraseScopeProvider.overrideWithValue(() async => scope),
      waitingPhraseClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 10, 29, 10),
      ),
      speechInputProvider.overrideWithValue(
        const _Heard('Купил кофе за три пятьдесят'),
      ),
      financeCaptureContextSourceProvider.overrideWithValue(
        const _CaptureAt('2026-10-29T10:00:00.000Z'),
      ),
      if (repository != null)
        financeEntryRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

/// The store, in memory: what is kept, and for which account it was asked.
final class MemoryWaitingPhraseStore implements WaitingPhraseStore {
  MemoryWaitingPhraseStore({
    List<WaitingPhrase> initial = const [],
    this.full = false,
  }) : phrases = List.of(initial);

  final List<WaitingPhrase> phrases;
  final bool full;
  final List<String> scopes = [];

  @override
  Future<List<WaitingPhrase>> read({
    required String scopeId,
    required DateTime now,
  }) async {
    scopes.add(scopeId);
    return List.of(phrases);
  }

  @override
  Future<List<WaitingPhrase>?> add({
    required String scopeId,
    required WaitingPhrase phrase,
    required DateTime now,
  }) async {
    scopes.add(scopeId);
    if (full) return null;
    phrases.add(phrase);
    return List.of(phrases);
  }

  @override
  Future<List<WaitingPhrase>> remove({
    required String scopeId,
    required String id,
    required DateTime now,
  }) async {
    scopes.add(scopeId);
    phrases.removeWhere((phrase) => phrase.id == id);
    return List.of(phrases);
  }

  @override
  Future<void> clear() async => phrases.clear();
}

final class _Heard implements SpeechInput {
  const _Heard(this.text);

  final String text;

  @override
  Future<SpeechResult> listen({
    required String languageTag,
    required String prompt,
  }) async => SpeechHeard(text);
}

final class _CaptureAt implements FinanceCaptureContextSource {
  const _CaptureAt(this.instant);

  final String instant;

  @override
  Future<FinanceCaptureContext> capture({
    required String canonicalTimezone,
  }) async => FinanceCaptureContext.fromPlatformValue({
    'capturedAtUtc': instant,
    'osTimezone': 'Europe/Kyiv',
    'osLocalDate': instant.substring(0, 10),
    'canonicalTimezone': configuredHomeApiTimezone,
    'canonicalLocalDate': instant.substring(0, 10),
  }, expectedCanonicalTimezone: configuredHomeApiTimezone);
}

final class _ParseRepository implements FinanceEntryRepositoryClient {
  _ParseRepository.answering() : failure = null;

  _ParseRepository.failing(FinanceEntryFailureKind this.failure);

  final FinanceEntryFailureKind? failure;
  final List<({String text, String capturedAt, String capturedTimezone})>
  calls = [];

  @override
  Future<FinanceEntryResult<OperationProposal>> parseOperationText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
    required String accountCurrency,
  }) async {
    calls.add((
      text: text,
      capturedAt: capturedAt,
      capturedTimezone: capturedTimezone,
    ));
    final kind = failure;
    if (kind != null) {
      return FinanceEntryFailureResult<OperationProposal>(
        FinanceEntryFailure(kind: kind, requestId: 'req_synthetic'),
      );
    }
    return const FinanceEntrySuccess<OperationProposal>(
      requestId: 'req_synthetic',
      value: OperationProposal(
        type: FinanceOperationType.expense,
        amount: '80',
        currency: 'EUR',
        occurredOn: '2026-10-25',
        sourceExpression: 'вчера',
        categoryId: null,
        category: null,
        gaps: [OperationParseGap.categoryNotMatched],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
