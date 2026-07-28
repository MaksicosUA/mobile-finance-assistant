import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Time context captured atomically by the native mobile platform.
///
/// The two date values are UTC [DateTime] carriers for calendar dates only;
/// their time component is always midnight and must not be interpreted as the
/// instant at which the finance command was captured.
@immutable
class FinanceCaptureContext {
  const FinanceCaptureContext._({
    required this.capturedAtUtc,
    required this.capturedTimezone,
    required this.osLocalDate,
    required this.canonicalTimezone,
    required this.canonicalLocalDate,
  });

  factory FinanceCaptureContext.fromPlatformValue(
    Object? value, {
    required String expectedCanonicalTimezone,
  }) {
    if (value is! Map<Object?, Object?> ||
        !_hasExactKeys(value, _responseKeys)) {
      throw const FormatException('Invalid finance capture context.');
    }

    final capturedAtWire = _requiredString(value, 'capturedAtUtc');
    final capturedTimezone = _validatedTimezone(
      _requiredString(value, 'osTimezone'),
    );
    final canonicalTimezone = _validatedTimezone(
      _requiredString(value, 'canonicalTimezone'),
    );
    final expectedTimezone = _validatedTimezone(expectedCanonicalTimezone);
    if (canonicalTimezone != expectedTimezone) {
      throw const FormatException('Unexpected canonical timezone.');
    }

    final capturedAtUtc = _parseUtcInstant(capturedAtWire);
    final osLocalDate = _parseDate(_requiredString(value, 'osLocalDate'));
    final canonicalLocalDate = _parseDate(
      _requiredString(value, 'canonicalLocalDate'),
    );
    final capturedUtcDate = DateTime.utc(
      capturedAtUtc.year,
      capturedAtUtc.month,
      capturedAtUtc.day,
    );
    if (!_isPlausibleLocalDate(osLocalDate, capturedUtcDate) ||
        !_isPlausibleLocalDate(canonicalLocalDate, capturedUtcDate)) {
      throw const FormatException('Inconsistent finance capture context.');
    }

    return FinanceCaptureContext._(
      capturedAtUtc: capturedAtUtc,
      capturedTimezone: capturedTimezone,
      osLocalDate: osLocalDate,
      canonicalTimezone: canonicalTimezone,
      canonicalLocalDate: canonicalLocalDate,
    );
  }

  final DateTime capturedAtUtc;
  final String capturedTimezone;
  final DateTime osLocalDate;
  final String canonicalTimezone;
  final DateTime canonicalLocalDate;
}

abstract interface class FinanceCaptureContextSource {
  Future<FinanceCaptureContext> capture({required String canonicalTimezone});
}

class PlatformFinanceCaptureContextSource
    implements FinanceCaptureContextSource {
  const PlatformFinanceCaptureContextSource()
    : _channel = const MethodChannel(_channelName);

  @visibleForTesting
  const PlatformFinanceCaptureContextSource.withChannel(this._channel);

  static const _channelName =
      'com.mobilefinanceassistant/finance_capture_context';

  final MethodChannel _channel;

  @override
  Future<FinanceCaptureContext> capture({
    required String canonicalTimezone,
  }) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedError(
        'Finance capture context is unavailable on this platform.',
      );
    }
    final expectedTimezone = _validatedTimezone(canonicalTimezone);
    final value = await _channel.invokeMethod<Object?>('capture', {
      'canonicalTimezone': expectedTimezone,
    });
    return FinanceCaptureContext.fromPlatformValue(
      value,
      expectedCanonicalTimezone: expectedTimezone,
    );
  }
}

const _responseKeys = <String>{
  'capturedAtUtc',
  'osTimezone',
  'osLocalDate',
  'canonicalTimezone',
  'canonicalLocalDate',
};

final _utcInstantPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$',
);
final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _timezonePattern = RegExp(r'^[A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+-]+)*$');
const _unstableTimezoneKeys = {'Factory', 'localtime', 'posixrules'};

bool _hasExactKeys(Map<Object?, Object?> value, Set<String> expected) {
  if (value.length != expected.length) return false;
  return value.keys.every((key) => key is String && expected.contains(key));
}

String _requiredString(Map<Object?, Object?> value, String key) {
  final candidate = value[key];
  if (candidate is! String) {
    throw const FormatException('Invalid finance capture context.');
  }
  return candidate;
}

String _validatedTimezone(String value) {
  if (value.isEmpty ||
      value.length > 128 ||
      value != value.trim() ||
      _unstableTimezoneKeys.contains(value) ||
      !_timezonePattern.hasMatch(value) ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw const FormatException('Invalid IANA timezone.');
  }
  return value;
}

DateTime _parseUtcInstant(String value) {
  if (!_utcInstantPattern.hasMatch(value)) {
    throw const FormatException('Invalid UTC capture instant.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !parsed.isUtc ||
      parsed.year < 1900 ||
      parsed.year > 2100) {
    throw const FormatException('Invalid UTC capture instant.');
  }
  return parsed;
}

DateTime _parseDate(String value) {
  if (!_datePattern.hasMatch(value)) {
    throw const FormatException('Invalid local date.');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null ||
      parsed.year < 1900 ||
      parsed.year > 2100 ||
      _dateWire(parsed) != value) {
    throw const FormatException('Invalid local date.');
  }
  return parsed;
}

bool _isPlausibleLocalDate(DateTime value, DateTime utcDate) {
  final dayDifference = value.difference(utcDate).inDays;
  return dayDifference >= -1 && dayDifference <= 1;
}

String _dateWire(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
