import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Something said while the app listens through pauses.
sealed class SpeechSessionEvent {
  const SpeechSessionEvent();
}

/// Everything heard so far, the words still being said included. Empty when
/// listening has begun and nothing has been heard yet.
final class SpeechSessionHearing extends SpeechSessionEvent {
  const SpeechSessionHearing(this.text);

  final String text;
}

/// Why listening stopped.
enum SpeechSessionEnd {
  /// The person tapped Done, or left the app.
  done,

  /// Nobody spoke for long enough that listening stopped on its own.
  silence,

  /// The person changed their mind.
  cancelled,

  /// The microphone was refused. The voice input screen needs no permission
  /// and is what is used instead.
  permissionDenied,

  /// This phone has nothing to listen with this way.
  unavailable,

  /// The recogniser needed a connection, or a downloaded language, it lacked.
  needsNetwork,

  failed,
}

/// The last event of every session. [text] is what was heard before it
/// stopped, and is empty when the person cancelled.
final class SpeechSessionEnded extends SpeechSessionEvent {
  const SpeechSessionEnded(this.reason, [this.text = '']);

  final SpeechSessionEnd reason;
  final String text;
}

/// Listens until the person says they are done, rather than until the first
/// pause (ADR 0031 amendment).
///
/// The phone's recognition service does the recognising, as with the voice
/// input screen; this app is handed text and never audio.
abstract interface class SpeechSession {
  /// One session: hearing events, then exactly one [SpeechSessionEnded].
  /// Cancelling the subscription cancels the session.
  Stream<SpeechSessionEvent> listen({required String languageTag});

  /// Stops listening and keeps what was heard: the stream then ends with
  /// [SpeechSessionEnd.done].
  Future<void> finish();
}

/// Reached through a method channel and an event channel, like the voice
/// input screen: nothing third-party stands between the person and what they
/// say about their money.
class PlatformSpeechSession implements SpeechSession {
  const PlatformSpeechSession();

  static const MethodChannel _methods = MethodChannel(
    'com.mobilefinanceassistant/speech_session',
  );
  static const EventChannel _events = EventChannel(
    'com.mobilefinanceassistant/speech_session/events',
  );

  @override
  Stream<SpeechSessionEvent> listen({required String languageTag}) async* {
    if (defaultTargetPlatform != TargetPlatform.android) {
      yield const SpeechSessionEnded(SpeechSessionEnd.unavailable);
      return;
    }
    // Asked first, through a method that fails cleanly on a build without
    // the channel. The microphone permission is requested here, so nothing
    // listens until it is granted.
    final String? status;
    try {
      status = await _methods.invokeMethod<String>('prepare');
    } on MissingPluginException {
      yield const SpeechSessionEnded(SpeechSessionEnd.unavailable);
      return;
    } on PlatformException {
      yield const SpeechSessionEnded(SpeechSessionEnd.failed);
      return;
    }
    switch (status) {
      case 'ready':
        break;
      case 'denied':
        yield const SpeechSessionEnded(SpeechSessionEnd.permissionDenied);
        return;
      case 'unavailable':
        yield const SpeechSessionEnded(SpeechSessionEnd.unavailable);
        return;
      default:
        // 'busy', and anything this build does not know.
        yield const SpeechSessionEnded(SpeechSessionEnd.failed);
        return;
    }

    var heard = '';
    await for (final raw in _events.receiveBroadcastStream(<String, Object?>{
      'languageTag': languageTag,
    })) {
      if (raw is! Map) continue;
      final text = switch (raw['text']) {
        final String value => value.trim(),
        _ => heard,
      };
      switch (raw['type']) {
        case 'text':
          heard = text;
          yield SpeechSessionHearing(text);
        case 'ended':
          yield SpeechSessionEnded(_reason(raw['reason']), text);
          return;
      }
    }
    // The channel closed without saying why. What was heard is not lost.
    yield SpeechSessionEnded(SpeechSessionEnd.failed, heard);
  }

  @override
  Future<void> finish() async {
    try {
      await _methods.invokeMethod<void>('finish');
    } on Object {
      // Nothing is listening, which is what finishing wanted.
    }
  }

  static SpeechSessionEnd _reason(Object? value) => switch (value) {
    'done' => SpeechSessionEnd.done,
    'silence' => SpeechSessionEnd.silence,
    'cancelled' => SpeechSessionEnd.cancelled,
    'permissionDenied' => SpeechSessionEnd.permissionDenied,
    'unavailable' => SpeechSessionEnd.unavailable,
    'network' => SpeechSessionEnd.needsNetwork,
    _ => SpeechSessionEnd.failed,
  };
}

/// Replaceable so a test can speak without a phone.
final speechSessionProvider = Provider<SpeechSession>(
  (ref) => const PlatformSpeechSession(),
);
