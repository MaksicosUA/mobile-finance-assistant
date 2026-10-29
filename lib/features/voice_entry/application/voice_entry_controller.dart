import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/speech_input.dart';
import '../../auth/application/auth_controller.dart';

/// The language the recogniser listens for. Russian because the sentence
/// parser reads Russian (ADR 0022): recognising another language would only
/// produce a sentence nothing can read.
const voiceEntryLanguageTag = 'ru-RU';

/// A sentence spoken on Home, waiting for the entry form to take it.
///
/// Taken once: the form reads it when it first appears and it is gone, so a
/// form rebuilt later — after switching wallets, say — does not read the same
/// words over what the person has since typed. Dropped on any other
/// navigation and with the account, never stored.
final spokenSentenceProvider = NotifierProvider<SpokenSentence, String?>(
  SpokenSentence.new,
);

class SpokenSentence extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(authAccountEpochProvider);
    return null;
  }

  void put(String text) => state = text;

  String? take() {
    final text = state;
    state = null;
    return text;
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
/// confirmation is still what writes an operation.
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
          .listen(languageTag: voiceEntryLanguageTag, prompt: prompt);
      switch (result) {
        case SpeechHeard(:final text):
          ref.read(spokenSentenceProvider.notifier).put(text);
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
}
