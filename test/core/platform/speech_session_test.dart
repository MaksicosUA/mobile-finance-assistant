import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/platform/speech_session.dart';

/// The channel to the app's own listening, which waits through pauses
/// (ADR 0031 amendment).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('com.mobilefinanceassistant/speech_session');
  const events = EventChannel(
    'com.mobilefinanceassistant/speech_session/events',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  /// The phone answers `prepare` with [status], then says [said].
  ({List<MethodCall> calls, List<Object?> listened, List<Object?> cancelled})
  phone(Object? status, {List<Object?> said = const [], bool close = true}) {
    final calls = <MethodCall>[];
    final listened = <Object?>[];
    final cancelled = <Object?>[];
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (status is PlatformException) throw status;
      return call.method == 'prepare' ? status : null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          listened.add(arguments);
          for (final event in said) {
            sink.success(event);
          }
          if (close) sink.endOfStream();
        },
        onCancel: cancelled.add,
      ),
    );
    return (calls: calls, listened: listened, cancelled: cancelled);
  }

  Future<List<SpeechSessionEvent>> listen() =>
      const PlatformSpeechSession().listen(languageTag: 'uk-UA').toList();

  test('asks first, then listens in the language it was given', () async {
    final channel = phone(
      'ready',
      said: [
        {'type': 'text', 'text': ''},
        {'type': 'text', 'text': 'заробив сьогодні'},
        {'type': 'text', 'text': 'заробив сьогодні 280 гривень'},
        {
          'type': 'ended',
          'reason': 'done',
          'text': 'заробив сьогодні 280 гривень',
        },
      ],
    );

    final heard = await listen();

    expect(channel.calls.single.method, 'prepare');
    expect(channel.listened, [
      {'languageTag': 'uk-UA'},
    ]);
    expect(
      [
        for (final event in heard)
          if (event case SpeechSessionHearing(:final text)) text,
      ],
      ['', 'заробив сьогодні', 'заробив сьогодні 280 гривень'],
    );
    final end = heard.last as SpeechSessionEnded;
    expect(end.reason, SpeechSessionEnd.done);
    expect(end.text, 'заробив сьогодні 280 гривень');
  });

  for (final (reason, expected) in const [
    ('done', SpeechSessionEnd.done),
    ('silence', SpeechSessionEnd.silence),
    ('cancelled', SpeechSessionEnd.cancelled),
    ('network', SpeechSessionEnd.needsNetwork),
    ('permissionDenied', SpeechSessionEnd.permissionDenied),
    ('unavailable', SpeechSessionEnd.unavailable),
    ('failed', SpeechSessionEnd.failed),
    ('something new', SpeechSessionEnd.failed),
  ]) {
    test('the phone saying "$reason" reads as $expected', () async {
      phone(
        'ready',
        said: [
          {'type': 'ended', 'reason': reason, 'text': ' кава 50 '},
        ],
      );

      final end = (await listen()).single as SpeechSessionEnded;

      expect(end.reason, expected);
      expect(end.text, 'кава 50');
    });
  }

  for (final (status, expected) in [
    ('denied', SpeechSessionEnd.permissionDenied),
    ('unavailable', SpeechSessionEnd.unavailable),
    ('busy', SpeechSessionEnd.failed),
    (null, SpeechSessionEnd.failed),
    (PlatformException(code: 'X'), SpeechSessionEnd.failed),
  ]) {
    test('a phone that answers "$status" is never listened to', () async {
      final channel = phone(status);

      final heard = await listen();

      expect((heard.single as SpeechSessionEnded).reason, expected);
      // Nothing listens until the microphone is the app's.
      expect(channel.listened, isEmpty);
    });
  }

  test('a build without the channel has nothing to listen with', () async {
    final heard = await listen();

    expect(
      (heard.single as SpeechSessionEnded).reason,
      SpeechSessionEnd.unavailable,
    );
  });

  test('another platform has nothing to listen with', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final channel = phone('ready');

    final heard = await listen();

    expect(
      (heard.single as SpeechSessionEnded).reason,
      SpeechSessionEnd.unavailable,
    );
    expect(channel.calls, isEmpty);
  });

  test('a channel that closes without a word keeps what was heard', () async {
    phone(
      'ready',
      said: [
        {'type': 'text', 'text': 'кава 50'},
      ],
    );

    final end = (await listen()).last as SpeechSessionEnded;

    expect(end.reason, SpeechSessionEnd.failed);
    expect(end.text, 'кава 50');
  });

  test('cancelling the subscription cancels the listening', () async {
    final channel = phone(
      'ready',
      said: [
        {'type': 'text', 'text': ''},
      ],
      close: false,
    );
    final first = Completer<void>();
    final subscription = const PlatformSpeechSession()
        .listen(languageTag: 'ru-RU')
        .listen((_) {
          if (!first.isCompleted) first.complete();
        });
    await first.future;

    await subscription.cancel();

    expect(channel.cancelled, hasLength(1));
  });

  test('finishing asks the phone to stop and never throws', () async {
    final channel = phone('ready');
    await const PlatformSpeechSession().finish();
    expect(channel.calls.single.method, 'finish');

    messenger.setMockMethodCallHandler(methods, null);
    await const PlatformSpeechSession().finish();
  });
}
