import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/canonical_timezone.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/platform/speech_input.dart';
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

  /// Null when the recogniser is already open.
  Future<VoiceEntryOutcome?> listen({required String prompt}) async {
    if (state) return null;
    state = true;
    try {
      final result = await ref
          .read(speechInputProvider)
          .listen(
            // The language of the app, which the sentence parser reads like
            // the other three (ADR 0034).
            languageTag: ref.read(appLanguageProvider).speechTag,
            prompt: prompt,
          );
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
      if (ref.mounted) state = false;
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
