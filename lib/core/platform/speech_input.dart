import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the phone's own speech recogniser answered (ADR 0031).
sealed class SpeechResult {
  const SpeechResult();
}

/// Words were heard. The text is all that ever reaches this app.
final class SpeechHeard extends SpeechResult {
  const SpeechHeard(this.text);

  final String text;
}

/// The person closed the recogniser without saying anything.
final class SpeechCancelled extends SpeechResult {
  const SpeechCancelled();
}

/// Something was said, and nothing in it was recognised as words.
final class SpeechNothingHeard extends SpeechResult {
  const SpeechNothingHeard();
}

/// The recogniser needed a connection it did not have.
final class SpeechNeedsNetwork extends SpeechResult {
  const SpeechNeedsNetwork();
}

/// This phone has no recogniser to hand the microphone to.
final class SpeechUnavailable extends SpeechResult {
  const SpeechUnavailable();
}

final class SpeechFailed extends SpeechResult {
  const SpeechFailed();
}

/// Turns speech into a sentence through the phone's own recogniser.
///
/// The recogniser is Android's voice input screen, the same one the keyboard's
/// microphone opens. It records and recognises in its own process: the audio
/// never enters this app or reaches our server, so there is nothing of it to
/// keep, encrypt or delete, and the app asks for no microphone permission.
abstract interface class SpeechInput {
  /// [languageTag] is the language to listen for, e.g. `ru-RU`; [prompt] is
  /// shown in the recogniser while it listens.
  Future<SpeechResult> listen({
    required String languageTag,
    required String prompt,
  });
}

/// Reached through a method channel rather than a package, like the update
/// installer and the share sheet: nothing third-party stands between the
/// person and what they say about their money.
class PlatformSpeechInput implements SpeechInput {
  const PlatformSpeechInput();

  static const MethodChannel _channel = MethodChannel(
    'com.mobilefinanceassistant/speech_input',
  );

  @override
  Future<SpeechResult> listen({
    required String languageTag,
    required String prompt,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SpeechUnavailable();
    }
    final Map<String, Object?>? reply;
    try {
      reply = await _channel.invokeMapMethod<String, Object?>(
        'listen',
        <String, Object?>{'languageTag': languageTag, 'prompt': prompt},
      );
    } on MissingPluginException {
      return const SpeechUnavailable();
    } on PlatformException {
      return const SpeechFailed();
    }
    return switch (reply?['status']) {
      'heard' => switch (reply?['text']) {
        final String text when text.trim().isNotEmpty => SpeechHeard(
          text.trim(),
        ),
        _ => const SpeechNothingHeard(),
      },
      'cancelled' => const SpeechCancelled(),
      'noMatch' => const SpeechNothingHeard(),
      'network' => const SpeechNeedsNetwork(),
      'unavailable' => const SpeechUnavailable(),
      // 'busy' and anything this build does not know.
      _ => const SpeechFailed(),
    };
  }
}

/// Replaceable so a test can speak without a phone.
final speechInputProvider = Provider<SpeechInput>(
  (ref) => const PlatformSpeechInput(),
);
