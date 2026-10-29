import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/platform/speech_input.dart';

/// The channel to the phone's own recogniser (ADR 0031).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilefinanceassistant/speech_input');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<SpeechResult> answer(Object? reply, {List<MethodCall>? calls}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls?.add(call);
      if (reply is PlatformException) throw reply;
      return reply;
    });
    return const PlatformSpeechInput().listen(
      languageTag: 'ru-RU',
      prompt: 'Скажите, например',
    );
  }

  test('asks for Russian and shows the prompt', () async {
    final calls = <MethodCall>[];
    await answer({'status': 'cancelled'}, calls: calls);

    expect(calls.single.method, 'listen');
    expect(calls.single.arguments, {
      'languageTag': 'ru-RU',
      'prompt': 'Скажите, например',
    });
  });

  test('what was heard comes back as text, trimmed', () async {
    final result = await answer({
      'status': 'heard',
      'text': '  Потратил 12,50 на продукты ',
    });

    expect((result as SpeechHeard).text, 'Потратил 12,50 на продукты');
  });

  for (final (reply, expected) in [
    ({'status': 'heard', 'text': '   '}, SpeechNothingHeard),
    ({'status': 'heard'}, SpeechNothingHeard),
    ({'status': 'noMatch'}, SpeechNothingHeard),
    ({'status': 'cancelled'}, SpeechCancelled),
    ({'status': 'network'}, SpeechNeedsNetwork),
    ({'status': 'unavailable'}, SpeechUnavailable),
    ({'status': 'busy'}, SpeechFailed),
    ({'status': 'something new'}, SpeechFailed),
    (null, SpeechFailed),
  ]) {
    test('$reply reads as $expected', () async {
      expect((await answer(reply)).runtimeType, expected);
    });
  }

  test('a failure on the phone is a failure, not an exception', () async {
    final result = await answer(PlatformException(code: 'SPEECH_INPUT_FAILED'));

    expect(result, isA<SpeechFailed>());
  });

  test('a build without the channel has no recogniser', () async {
    expect(
      await const PlatformSpeechInput().listen(
        languageTag: 'ru-RU',
        prompt: '',
      ),
      isA<SpeechUnavailable>(),
    );
  });

  test('anywhere but Android there is no recogniser to hand to', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = <MethodCall>[];

    final result = await answer({'status': 'heard', 'text': 'x'}, calls: calls);

    expect(result, isA<SpeechUnavailable>());
    expect(calls, isEmpty);
  });
}
