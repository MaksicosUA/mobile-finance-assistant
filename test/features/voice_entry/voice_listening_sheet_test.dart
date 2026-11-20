import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/core/platform/finance_capture_context.dart';
import 'package:mobile_finance_assistant/core/platform/speech_input.dart';
import 'package:mobile_finance_assistant/core/platform/speech_session.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/voice_entry/application/voice_entry_controller.dart';
import 'package:mobile_finance_assistant/features/voice_entry/presentation/voice_listening_sheet.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

/// The screen that listens through pauses until Done (ADR 0031 amendment).
void main() {
  testWidgets('shows what is heard as it is said, and Done hands it over', (
    tester,
  ) async {
    final session = _FakeSession();
    final outcomes = await _pump(tester, session);

    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    // Nothing yet: Android may still be asking for the microphone.
    expect(find.byKey(const Key('voice-listening-sheet')), findsNothing);

    session.hear('');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-listening-sheet')), findsOneWidget);
    expect(find.text('Пока ничего не слышно'), findsOneWidget);

    session.hear('заработал сегодня');
    await tester.pumpAndSettle();
    // A pause is not the end: the screen stays and keeps what it has.
    expect(find.text('заработал сегодня'), findsOneWidget);
    session.hear('заработал сегодня 280 гривен');
    await tester.pumpAndSettle();
    expect(find.text('заработал сегодня 280 гривен'), findsOneWidget);

    await tester.tap(find.byKey(const Key('voice-listening-done')));
    await tester.pump();
    expect(session.finished, 1);
    session.end(SpeechSessionEnd.done, 'заработал сегодня 280 гривен');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-listening-sheet')), findsNothing);
    expect(outcomes, [VoiceEntryOutcome.heard]);
  });

  testWidgets('cancel closes it and keeps nothing', (tester) async {
    final session = _FakeSession();
    final outcomes = await _pump(tester, session);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    session.hear('потратил 50');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('voice-listening-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-listening-sheet')), findsNothing);
    expect(session.cancelled, isTrue);
    expect(outcomes, [VoiceEntryOutcome.cancelled]);
  });

  testWidgets('back is cancel, never a microphone left listening', (
    tester,
  ) async {
    final session = _FakeSession();
    final outcomes = await _pump(tester, session);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    session.hear('потратил 50');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-listening-sheet')), findsNothing);
    expect(session.cancelled, isTrue);
    expect(outcomes, [VoiceEntryOutcome.cancelled]);
  });

  testWidgets('a tap outside is cancel too', (tester) async {
    final session = _FakeSession();
    final outcomes = await _pump(tester, session);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    session.hear('');
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-listening-sheet')), findsNothing);
    expect(outcomes, [VoiceEntryOutcome.cancelled]);
  });

  testWidgets('silence closes it on its own with what was heard', (
    tester,
  ) async {
    final session = _FakeSession();
    final outcomes = await _pump(tester, session);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    session.hear('кофе 50');
    await tester.pumpAndSettle();

    session.end(SpeechSessionEnd.silence, 'кофе 50');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-listening-sheet')), findsNothing);
    expect(outcomes, [VoiceEntryOutcome.heard]);
  });

  testWidgets('the screen goes the moment listening stops', (tester) async {
    // Keeping the words on the phone may take a while; the person is not
    // made to watch a screen that has stopped listening meanwhile.
    final session = _FakeSession();
    final outcomes = await _pump(tester, session, capture: _SlowCapture());
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    session.hear('кофе 50');
    await tester.pumpAndSettle();

    session.end(SpeechSessionEnd.done, 'кофе 50');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-listening-sheet')), findsNothing);
    expect(outcomes, isEmpty);
  });

  testWidgets('a refused microphone opens no screen of ours', (tester) async {
    final session = _FakeSession();
    final dialog = _FakeSpeech();
    final outcomes = await _pump(tester, session, dialog: dialog);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();

    session.end(SpeechSessionEnd.permissionDenied);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-listening-sheet')), findsNothing);
    expect(dialog.opened, 1);
    expect(outcomes, [VoiceEntryOutcome.cancelled]);
  });

  for (final (language, title, done) in const [
    (Locale('ru'), 'Слушаю', 'Готово'),
    (Locale('uk'), 'Слухаю', 'Готово'),
    (Locale('en'), 'Listening', 'Done'),
    (Locale('de'), 'Ich höre zu', 'Fertig'),
  ]) {
    testWidgets('fits 360 dp at 200% in ${language.languageCode}', (
      tester,
    ) async {
      final session = _FakeSession();
      await _pump(
        tester,
        session,
        locale: language,
        size: const Size(360, 780),
        textScale: 2,
      );
      await tester.tap(find.byKey(const Key('start')));
      await tester.pump();
      session.hear(
        'заработал сегодня 280 гривен на подработке и ещё купил продукты',
      );
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget);
      expect(find.text(done), findsOneWidget);
      expect(tester.takeException(), isNull);
      final button = tester.getSize(
        find.byKey(const Key('voice-listening-cancel')),
      );
      expect(button.height, greaterThanOrEqualTo(48));
    });
  }
}

Future<List<VoiceEntryOutcome?>> _pump(
  WidgetTester tester,
  _FakeSession session, {
  _FakeSpeech? dialog,
  FinanceCaptureContextSource capture = const _NoCapture(),
  Locale locale = const Locale('ru'),
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final outcomes = <VoiceEntryOutcome?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        speechSessionProvider.overrideWithValue(session),
        speechInputProvider.overrideWithValue(dialog ?? _FakeSpeech()),
        // Keeping the words on the phone is tested with the waiting phrases;
        // here it simply cannot happen, and the words still go to the form.
        financeCaptureContextSourceProvider.overrideWithValue(capture),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(AppAccent.teal),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: VoiceListeningHost(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: TextButton(
                  key: const Key('start'),
                  onPressed: () async {
                    outcomes.add(
                      await ref
                          .read(voiceEntryControllerProvider.notifier)
                          .listen(prompt: 'prompt'),
                    );
                  },
                  child: const Text('start'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return outcomes;
}

final class _FakeSession implements SpeechSession {
  StreamController<SpeechSessionEvent>? _events;
  int finished = 0;
  bool cancelled = false;

  @override
  Stream<SpeechSessionEvent> listen({required String languageTag}) {
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

  @override
  Future<void> finish() async => finished += 1;
}

/// The voice input screen, which a refused microphone falls back to.
final class _FakeSpeech implements SpeechInput {
  int opened = 0;

  @override
  Future<SpeechResult> listen({
    required String languageTag,
    required String prompt,
  }) async {
    opened += 1;
    return const SpeechCancelled();
  }
}

final class _NoCapture implements FinanceCaptureContextSource {
  const _NoCapture();

  @override
  Future<FinanceCaptureContext> capture({required String canonicalTimezone}) =>
      throw StateError('No clock on this phone.');
}

/// A clock that never answers, so keeping the words never finishes.
final class _SlowCapture implements FinanceCaptureContextSource {
  final _never = Completer<FinanceCaptureContext>();

  @override
  Future<FinanceCaptureContext> capture({required String canonicalTimezone}) =>
      _never.future;
}
