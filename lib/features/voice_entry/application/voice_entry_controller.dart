import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/canonical_timezone.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/platform/speech_input.dart';
import '../../../core/platform/speech_session.dart';
import '../../auth/application/auth_controller.dart';
import '../../finance_entry/application/finance_entry_controller.dart';
import '../domain/waiting_phrase.dart';
import 'waiting_phrases_controller.dart';

/// What the recogniser heard, on its way to the entry form.
@immutable
final class HeardSentence {
  const HeardSentence(this.text, {this.kept});

  final String text;

  /// The same words, kept on the phone until the server has read them
  /// (ADR 0032). Null when they could not be kept.
  final WaitingPhrase? kept;
}

/// A sentence spoken on Home, waiting for the entry form to take it.
///
/// Taken once: the form reads it when it first appears and it is gone, so a
/// form rebuilt later — after switching wallets, say — does not read the same
/// words over what the person has since typed. Dropped on any other
/// navigation and with the account. What outlives this hand-off is the kept
/// copy in [waitingPhrasesProvider], not this.
final spokenSentenceProvider = NotifierProvider<SpokenSentence, HeardSentence?>(
  SpokenSentence.new,
);

class SpokenSentence extends Notifier<HeardSentence?> {
  @override
  HeardSentence? build() {
    ref.watch(authAccountEpochProvider);
    return null;
  }

  void put(HeardSentence sentence) => state = sentence;

  HeardSentence? take() {
    final sentence = state;
    state = null;
    return sentence;
  }

  void discard() => state = null;
}

enum VoiceEntryOutcome {
  /// The sentence is waiting in [spokenSentenceProvider].
  heard,
  cancelled,
  nothingHeard,
  needsNetwork,
  unavailable,
  failed,
}

/// What the app has heard so far while it listens through pauses.
///
/// Null whenever it is not listening that way: the listening screen is shown
/// while this holds a value and goes away when it returns to null. Memory only,
/// like the sentence it becomes.
final voiceHeardSoFarProvider = NotifierProvider<VoiceHeardSoFar, String?>(
  VoiceHeardSoFar.new,
);

class VoiceHeardSoFar extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String text) => state = text;

  void clear() => state = null;
}

/// Whether the recogniser is open, so Home does not open a second one.
final voiceEntryControllerProvider =
    NotifierProvider<VoiceEntryController, bool>(VoiceEntryController.new);

/// Asks the phone's recogniser for a sentence (ADR 0031).
///
/// What it hears is a proposal source like typing is, nothing more: the
/// sentence goes to the same field and the same parser, and the same
/// confirmation is still what writes an operation. It is kept on the phone
/// first, with the moment it was said, so that no connection — or no entry
/// screen — loses it (ADR 0032).
class VoiceEntryController extends Notifier<bool> {
  @override
  bool build() => false;

  StreamSubscription<SpeechSessionEvent>? _session;
  Completer<SpeechResult?>? _sessionResult;

  /// Null when the recogniser is already open.
  ///
  /// The app's own listening screen first, which waits through pauses until
  /// the person taps Done. When the microphone is refused, or this phone has
  /// no recogniser to listen with that way, the voice input screen is used
  /// instead, as before (ADR 0031 amendment).
  Future<VoiceEntryOutcome?> listen({required String prompt}) async {
    if (state) return null;
    state = true;
    try {
      // The language of the app, which the sentence parser reads like the
      // other three (ADR 0034).
      final languageTag = ref.read(appLanguageProvider).speechTag;
      final throughPauses = await _listenThroughPauses(languageTag);
      // The listening screen goes the moment listening stops, not once the
      // words have been put away below.
      if (ref.mounted) ref.read(voiceHeardSoFarProvider.notifier).clear();
      final result =
          throughPauses ??
          await ref
              .read(speechInputProvider)
              .listen(languageTag: languageTag, prompt: prompt);
      switch (result) {
        case SpeechHeard(:final text):
          final kept = await _keep(text);
          ref
              .read(spokenSentenceProvider.notifier)
              .put(HeardSentence(text, kept: kept));
          return VoiceEntryOutcome.heard;
        case SpeechCancelled():
          return VoiceEntryOutcome.cancelled;
        case SpeechNothingHeard():
          return VoiceEntryOutcome.nothingHeard;
        case SpeechNeedsNetwork():
          return VoiceEntryOutcome.needsNetwork;
        case SpeechUnavailable():
          return VoiceEntryOutcome.unavailable;
        case SpeechFailed():
          return VoiceEntryOutcome.failed;
      }
    } finally {
      if (ref.mounted) {
        ref.read(voiceHeardSoFarProvider.notifier).clear();
        state = false;
      }
    }
  }

  /// The person is done: what is being said now is still taken.
  Future<void> finish() async {
    if (_session == null) return;
    await ref.read(speechSessionProvider).finish();
  }

  /// The person changed their mind: nothing heard goes anywhere.
  Future<void> cancel() async {
    final session = _session;
    final result = _sessionResult;
    if (session == null || result == null) return;
    _session = null;
    _sessionResult = null;
    if (!result.isCompleted) result.complete(const SpeechCancelled());
    // Not awaited: a session still asking for the microphone ends only once
    // it has an answer, and the person should not wait for that.
    unawaited(session.cancel());
  }

  /// Null when this way of listening cannot be used here, so the voice input
  /// screen should be.
  Future<SpeechResult?> _listenThroughPauses(String languageTag) {
    final result = Completer<SpeechResult?>();
    _sessionResult = result;
    _session = ref
        .read(speechSessionProvider)
        .listen(languageTag: languageTag)
        .listen(
          (event) {
            if (result.isCompleted) return;
            switch (event) {
              case SpeechSessionHearing(:final text):
                ref.read(voiceHeardSoFarProvider.notifier).show(text);
              case SpeechSessionEnded(:final reason, :final text):
                result.complete(_resultOf(reason, text));
            }
          },
          onError: (Object _) {
            if (!result.isCompleted) result.complete(const SpeechFailed());
          },
          onDone: () {
            if (!result.isCompleted) result.complete(const SpeechFailed());
          },
          cancelOnError: true,
        );
    return result.future.whenComplete(() {
      _session = null;
      _sessionResult = null;
    });
  }

  /// What a session that stopped amounts to. Whatever was heard before it
  /// stopped is kept, whatever stopped it: a lost connection halfway through
  /// a sentence does not unsay the half that was heard.
  static SpeechResult? _resultOf(SpeechSessionEnd reason, String text) {
    final heard = text.trim();
    switch (reason) {
      case SpeechSessionEnd.cancelled:
        return const SpeechCancelled();
      case SpeechSessionEnd.permissionDenied || SpeechSessionEnd.unavailable
          when heard.isEmpty:
        return null;
      case _ when heard.isNotEmpty:
        return SpeechHeard(heard);
      case SpeechSessionEnd.needsNetwork:
        return const SpeechNeedsNetwork();
      case SpeechSessionEnd.done || SpeechSessionEnd.silence:
        return const SpeechNothingHeard();
      case SpeechSessionEnd.permissionDenied ||
          SpeechSessionEnd.unavailable ||
          SpeechSessionEnd.failed:
        return const SpeechFailed();
    }
  }

  Future<WaitingPhrase?> _keep(String text) async {
    try {
      final capture = await ref
          .read(financeCaptureContextSourceProvider)
          .capture(canonicalTimezone: ref.read(canonicalTimezoneProvider));
      return await ref
          .read(waitingPhrasesProvider.notifier)
          .keep(text: text, capture: capture);
    } on Object {
      // Not kept is not a refusal: the words still reach the form below.
      return null;
    }
  }
}
