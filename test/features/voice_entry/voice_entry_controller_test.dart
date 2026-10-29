import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/platform/speech_input.dart';
import 'package:mobile_finance_assistant/features/voice_entry/application/voice_entry_controller.dart';

/// Speaking on Home hands a sentence to the entry form, and nothing else
/// (ADR 0031).
void main() {
  test('a heard sentence waits for the form, once', () async {
    final container = _container(const SpeechHeard('Потратил 20 на кофе'));
    addTearDown(container.dispose);

    final outcome = await container
        .read(voiceEntryControllerProvider.notifier)
        .listen(prompt: 'prompt');

    expect(outcome, VoiceEntryOutcome.heard);
    final spoken = container.read(spokenSentenceProvider.notifier);
    expect(spoken.take()?.text, 'Потратил 20 на кофе');
    // Taken, not peeked: a form rebuilt later does not read it again.
    expect(spoken.take(), isNull);
  });

  test('it listens for Russian, the language the parser reads', () async {
    final speech = _FakeSpeech(const SpeechCancelled());
    final container = ProviderContainer(
      overrides: [speechInputProvider.overrideWithValue(speech)],
    );
    addTearDown(container.dispose);

    await container
        .read(voiceEntryControllerProvider.notifier)
        .listen(prompt: 'Скажите');

    expect(speech.languageTags, ['ru-RU']);
    expect(speech.prompts, ['Скажите']);
  });

  for (final (result, outcome) in [
    (const SpeechCancelled(), VoiceEntryOutcome.cancelled),
    (const SpeechNothingHeard(), VoiceEntryOutcome.nothingHeard),
    (const SpeechNeedsNetwork(), VoiceEntryOutcome.needsNetwork),
    (const SpeechUnavailable(), VoiceEntryOutcome.unavailable),
    (const SpeechFailed(), VoiceEntryOutcome.failed),
  ]) {
    test('$outcome leaves nothing for the form', () async {
      final container = _container(result);
      addTearDown(container.dispose);

      expect(
        await container
            .read(voiceEntryControllerProvider.notifier)
            .listen(prompt: 'prompt'),
        outcome,
      );
      expect(container.read(spokenSentenceProvider), isNull);
      expect(container.read(voiceEntryControllerProvider), isFalse);
    });
  }

  test('a second tap while the recogniser is open asks nothing', () async {
    final pending = Completer<SpeechResult>();
    final speech = _FakeSpeech.pending(pending.future);
    final container = ProviderContainer(
      overrides: [speechInputProvider.overrideWithValue(speech)],
    );
    addTearDown(container.dispose);
    final controller = container.read(voiceEntryControllerProvider.notifier);

    final first = controller.listen(prompt: 'prompt');
    expect(container.read(voiceEntryControllerProvider), isTrue);
    expect(await controller.listen(prompt: 'prompt'), isNull);

    pending.complete(const SpeechCancelled());
    expect(await first, VoiceEntryOutcome.cancelled);
    expect(speech.prompts, hasLength(1));
    expect(container.read(voiceEntryControllerProvider), isFalse);
  });
}

ProviderContainer _container(SpeechResult result) => ProviderContainer(
  overrides: [speechInputProvider.overrideWithValue(_FakeSpeech(result))],
);

final class _FakeSpeech implements SpeechInput {
  _FakeSpeech(SpeechResult result) : _answer = Future.value(result);
  _FakeSpeech.pending(this._answer);

  final Future<SpeechResult> _answer;
  final List<String> languageTags = [];
  final List<String> prompts = [];

  @override
  Future<SpeechResult> listen({
    required String languageTag,
    required String prompt,
  }) {
    languageTags.add(languageTag);
    prompts.add(prompt);
    return _answer;
  }
}
