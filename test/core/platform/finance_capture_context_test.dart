import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/platform/finance_capture_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FinanceCaptureContext', () {
    test('decodes one strict platform capture context', () {
      final context = FinanceCaptureContext.fromPlatformValue(
        _captureContext(),
        expectedCanonicalTimezone: 'Europe/Berlin',
      );

      expect(context.capturedAtUtc, DateTime.utc(2026, 7, 28, 23, 30));
      expect(context.capturedTimezone, 'America/New_York');
      expect(context.osLocalDate, DateTime.utc(2026, 7, 28));
      expect(context.canonicalTimezone, 'Europe/Berlin');
      expect(context.canonicalLocalDate, DateTime.utc(2026, 7, 29));
    });

    test('rejects a canonical timezone mismatch', () {
      expect(
        () => FinanceCaptureContext.fromPlatformValue(
          _captureContext(),
          expectedCanonicalTimezone: 'Europe/Paris',
        ),
        throwsFormatException,
      );
    });

    test('rejects unstable timezone keys and fixed offsets', () {
      for (final timezone in const [
        'Factory',
        'localtime',
        'posixrules',
        'GMT+02:00',
      ]) {
        expect(
          () => FinanceCaptureContext.fromPlatformValue(
            _captureContext(osTimezone: timezone),
            expectedCanonicalTimezone: 'Europe/Berlin',
          ),
          throwsFormatException,
          reason: timezone,
        );
      }
    });

    test('rejects non-UTC instants, invalid dates, and implausible dates', () {
      for (final value in [
        _captureContext(capturedAtUtc: '2026-07-28T23:30:00+02:00'),
        _captureContext(osLocalDate: '2026-02-30'),
        _captureContext(canonicalLocalDate: '2026-07-30'),
      ]) {
        expect(
          () => FinanceCaptureContext.fromPlatformValue(
            value,
            expectedCanonicalTimezone: 'Europe/Berlin',
          ),
          throwsFormatException,
        );
      }
    });

    test('rejects missing, extra, or wrongly typed fields', () {
      final missing = _captureContext()..remove('osLocalDate');
      final extra = _captureContext()..['offset'] = '+02:00';
      final wrongType = _captureContext()..['osLocalDate'] = 20260728;

      for (final value in [missing, extra, wrongType]) {
        expect(
          () => FinanceCaptureContext.fromPlatformValue(
            value,
            expectedCanonicalTimezone: 'Europe/Berlin',
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('PlatformFinanceCaptureContextSource', () {
    const channel = MethodChannel('finance_capture_context_test');

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('uses the same strict channel contract on Android and iOS', () async {
      final receivedCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            receivedCalls.add(call);
            return _captureContext();
          });
      const source = PlatformFinanceCaptureContextSource.withChannel(channel);

      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final context = await source.capture(
          canonicalTimezone: 'Europe/Berlin',
        );
        expect(context.canonicalLocalDate, DateTime.utc(2026, 7, 29));
      }

      expect(receivedCalls, hasLength(2));
      for (final call in receivedCalls) {
        expect(call.method, 'capture');
        expect(call.arguments, {'canonicalTimezone': 'Europe/Berlin'});
      }
    });

    test('fails closed outside supported mobile platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      const source = PlatformFinanceCaptureContextSource.withChannel(channel);

      await expectLater(
        source.capture(canonicalTimezone: 'Europe/Berlin'),
        throwsUnsupportedError,
      );
    });
  });
}

Map<Object?, Object?> _captureContext({
  String capturedAtUtc = '2026-07-28T23:30:00Z',
  String osTimezone = 'America/New_York',
  String osLocalDate = '2026-07-28',
  String canonicalTimezone = 'Europe/Berlin',
  String canonicalLocalDate = '2026-07-29',
}) => <Object?, Object?>{
  'capturedAtUtc': capturedAtUtc,
  'osTimezone': osTimezone,
  'osLocalDate': osLocalDate,
  'canonicalTimezone': canonicalTimezone,
  'canonicalLocalDate': canonicalLocalDate,
};
