import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/language/app_language.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/core/platform/speech_input.dart';
import 'package:mobile_finance_assistant/core/platform/speech_session.dart';
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

  for (final (language, tag) in const [
    (AppLanguage.russian, 'ru-RU'),
    (AppLanguage.ukrainian, 'uk-UA'),
    (AppLanguage.english, 'en-US'),
    (AppLanguage.german, 'de-DE'),
  ]) {
    test('it listens in the language of the app: $tag', () async {
      final speech = _FakeSpeech(const SpeechCancelled());
      final container = ProviderContainer(
        overrides: [
          speechInputProvider.overrideWithValue(speech),
          appLanguageProvider.overrideWithValue(language),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(voiceEntryControllerProvider.notifier)
          .listen(prompt: 'Скажите');

      expect(speech.languageTags, [tag]);
      expect(speech.prompts, ['Скажите']);
    });
  }

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
  group('listening through pauses', () {
    test('what is heard shows as it is said, and Done hands it over', () async {
      final session = _FakeSession();
      final dialog = _FakeSpeech(const SpeechCancelled());
      final container = _sessionContainer(session, dialog);
      addTearDown(container.dispose);
      final controller = container.read(voiceEntryControllerProvider.notifier);

      final outcome = controller.listen(prompt: 'prompt');
      await pumpEventQueue();
      expect(container.read(voiceHeardSoFarProvider), isNull);

      session.hear('');
      await pumpEventQueue();
      expect(container.read(voiceHeardSoFarProvider), '');
      session.hear('заработал сегодня');
      await pumpEventQueue();
      expect(container.read(voiceHeardSoFarProvider), 'заработал сегодня');

      await controller.finish();
      expect(session.finished, 1);
      session.end(SpeechSessionEnd.done, 'заработал сегодня 280 гривен');

      expect(await outcome, VoiceEntryOutcome.heard);
      expect(
        container.read(spokenSentenceProvider.notifier).take()?.text,
        'заработал сегодня 280 гривен',
      );
      // The window that stops at a pause was never opened.
      expect(dialog.prompts, isEmpty);
      expect(container.read(voiceHeardSoFarProvider), isNull);
      expect(container.read(voiceEntryControllerProvider), isFalse);
    });

    test('it listens in the language of the app', () async {
      final session = _FakeSession();
      final container = ProviderContainer(
        overrides: [
          speechSessionProvider.overrideWithValue(session),
          speechInputProvider.overrideWithValue(
            _FakeSpeech(const SpeechCancelled()),
          ),
          appLanguageProvider.overrideWithValue(AppLanguage.german),
        ],
      );
      addTearDown(container.dispose);

      final outcome = container
          .read(voiceEntryControllerProvider.notifier)
          .listen(prompt: 'prompt');
      await pumpEventQueue();
      session.end(SpeechSessionEnd.cancelled);
      await outcome;

      expect(session.languageTags, ['de-DE']);
    });

    test('cancel ends it at once and nothing reaches the form', () async {
      final session = _FakeSession();
      final container = _sessionContainer(session, _FakeSpeech(null));
      addTearDown(container.dispose);
      final controller = container.read(voiceEntryControllerProvider.notifier);

      final outcome = controller.listen(prompt: 'prompt');
      await pumpEventQueue();
      session.hear('потратил 50');
      await pumpEventQueue();

      await controller.cancel();

      expect(await outcome, VoiceEntryOutcome.cancelled);
      expect(session.cancelled, isTrue);
      expect(container.read(spokenSentenceProvider), isNull);
      expect(container.read(voiceHeardSoFarProvider), isNull);
      expect(container.read(voiceEntryControllerProvider), isFalse);
    });

    for (final (reason, text, outcome) in const [
      (SpeechSessionEnd.silence, 'кофе 50', VoiceEntryOutcome.heard),
      (SpeechSessionEnd.silence, '', VoiceEntryOutcome.nothingHeard),
      (SpeechSessionEnd.done, '', VoiceEntryOutcome.nothingHeard),
      // Half a sentence heard before the connection went is still said.
      (SpeechSessionEnd.needsNetwork, 'кофе 50', VoiceEntryOutcome.heard),
      (SpeechSessionEnd.needsNetwork, '', VoiceEntryOutcome.needsNetwork),
      (SpeechSessionEnd.failed, 'кофе 50', VoiceEntryOutcome.heard),
      (SpeechSessionEnd.failed, '', VoiceEntryOutcome.failed),
      (SpeechSessionEnd.cancelled, '', VoiceEntryOutcome.cancelled),
      // Cancelled means nothing goes on, whatever the phone still held.
      (SpeechSessionEnd.cancelled, 'кофе 50', VoiceEntryOutcome.cancelled),
    ]) {
      test('$reason with "$text" is $outcome', () async {
        final session = _FakeSession();
        final dialog = _FakeSpeech(null);
        final container = _sessionContainer(session, dialog);
        addTearDown(container.dispose);

        final result = container
            .read(voiceEntryControllerProvider.notifier)
            .listen(prompt: 'prompt');
        await pumpEventQueue();
        session.end(reason, text);

        expect(await result, outcome);
        expect(
          container.read(spokenSentenceProvider)?.text,
          outcome == VoiceEntryOutcome.heard ? text : null,
        );
        expect(dialog.prompts, isEmpty);
      });
    }

    for (final reason in const [
      SpeechSessionEnd.permissionDenied,
      SpeechSessionEnd.unavailable,
    ]) {
      test('$reason falls back to the voice input screen', () async {
        final session = _FakeSession();
        final dialog = _FakeSpeech(const SpeechHeard('кофе 50'));
        final container = _sessionContainer(session, dialog);
        addTearDown(container.dispose);

        final result = container
            .read(voiceEntryControllerProvider.notifier)
            .listen(prompt: 'Скажите');
        await pumpEventQueue();
        session.end(reason);

        expect(await result, VoiceEntryOutcome.heard);
        expect(dialog.prompts, ['Скажите']);
        expect(container.read(spokenSentenceProvider)?.text, 'кофе 50');
      });
    }

    test('a stream that just stops is a failure, not a hang', () async {
      final session = _FakeSession();
      final container = _sessionContainer(session, _FakeSpeech(null));
      addTearDown(container.dispose);

      final result = container
          .read(voiceEntryControllerProvider.notifier)
          .listen(prompt: 'prompt');
      await pumpEventQueue();
      await session.close();

      expect(await result, VoiceEntryOutcome.failed);
    });

    test('finish and cancel with nothing listening do nothing', () async {
      final session = _FakeSession();
      final container = _sessionContainer(session, _FakeSpeech(null));
      addTearDown(container.dispose);
      final controller = container.read(voiceEntryControllerProvider.notifier);

      await controller.finish();
      await controller.cancel();

      expect(session.finished, 0);
      expect(session.languageTags, isEmpty);
    });
  });
}

ProviderContainer _sessionContainer(_FakeSession session, _FakeSpeech dialog) =>
    ProviderContainer(
      overrides: [
        speechSessionProvider.overrideWithValue(session),
        speechInputProvider.overrideWithValue(dialog),
      ],
    );

/// A listening session the test speaks into.
final class _FakeSession implements SpeechSession {
  StreamController<SpeechSessionEvent>? _events;
  final List<String> languageTags = [];
  int finished = 0;
  bool cancelled = false;

  @override
  Stream<SpeechSessionEvent> listen({required String languageTag}) {
    languageTags.add(languageTag);
    final events = StreamController<SpeechSessionEvent>(
      onCancel: () => cancelled = true,
    );
    _events = events;
    return events.stream;
  }

  void hear(String text) => _events!.add(SpeechSessionHearing(text));

  void end(SpeechSessionEnd reason, [String text = '']) {
    _events!
      ..add(SpeechSessionEnded(reason, text))
      ..close();
  }

  Future<void> close() => _events!.close();

  @override
  Future<void> finish() async => finished += 1;
}

ProviderContainer _container(SpeechResult result) => ProviderContainer(
  overrides: [speechInputProvider.overrideWithValue(_FakeSpeech(result))],
);

final class _FakeSpeech implements SpeechInput {
  /// [result] null is a window that must never be opened.
  _FakeSpeech(SpeechResult? result)
    : _answer = result == null ? null : Future.value(result);
  _FakeSpeech.pending(this._answer);

  final Future<SpeechResult>? _answer;
  final List<String> languageTags = [];
  final List<String> prompts = [];

  @override
  Future<SpeechResult> listen({
    required String languageTag,
    required String prompt,
  }) {
    languageTags.add(languageTag);
    prompts.add(prompt);
    return _answer ?? (throw StateError('The voice input screen was opened.'));
  }
}
