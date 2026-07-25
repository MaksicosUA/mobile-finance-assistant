import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'home_dto.dart';

typedef HomeRequestIdFactory = String Function();
typedef HomeApiClock = DateTime Function();

sealed class HomeApiResult {
  const HomeApiResult({required this.requestId});

  /// A server-provided request ID when it is safe to display, otherwise the
  /// locally generated correlation ID.
  final String requestId;
}

abstract interface class HomeApiClient {
  Future<HomeApiResult> fetchHome({String? etag, String? accessToken});
}

@immutable
final class HomeApiData extends HomeApiResult {
  const HomeApiData({
    required super.requestId,
    required this.payload,
    required this.etag,
  });

  /// Deeply normalized, immutable JSON, already checked by [HomeDto.fromJson].
  final Map<String, Object?> payload;
  final String? etag;
}

@immutable
final class HomeApiNotModified extends HomeApiResult {
  const HomeApiNotModified({required super.requestId, required this.etag});

  final String? etag;
}

sealed class HomeApiFailure extends HomeApiResult {
  const HomeApiFailure({required super.requestId});
}

@immutable
final class HomeApiOfflineFailure extends HomeApiFailure {
  const HomeApiOfflineFailure({required super.requestId});
}

@immutable
final class HomeApiTimeoutFailure extends HomeApiFailure {
  const HomeApiTimeoutFailure({required super.requestId});
}

@immutable
final class HomeApiUnauthorizedFailure extends HomeApiFailure {
  const HomeApiUnauthorizedFailure({required super.requestId});
}

@immutable
final class HomeApiThrottledFailure extends HomeApiFailure {
  const HomeApiThrottledFailure({
    required super.requestId,
    required this.retryAfter,
  });

  final Duration? retryAfter;
}

@immutable
final class HomeApiServerFailure extends HomeApiFailure {
  const HomeApiServerFailure({
    required super.requestId,
    required this.statusCode,
  });

  final int statusCode;
}

@immutable
final class HomeApiMalformedFailure extends HomeApiFailure {
  const HomeApiMalformedFailure({required super.requestId});
}

@immutable
final class HomeApiOtherFailure extends HomeApiFailure {
  const HomeApiOtherFailure({
    required super.requestId,
    required this.statusCode,
  });

  final int? statusCode;
}

/// Read-only client for the versioned Home aggregate endpoint.
///
/// The client deliberately has no logging interceptor: Home payloads and
/// authorization headers contain sensitive data. The caller owns auth refresh,
/// caching, retry policy, and mapping the validated JSON into domain entities.
final class HomeApi implements HomeApiClient {
  HomeApi({
    required Dio dio,
    required Uri baseUri,
    required String timezone,
    HomeRequestIdFactory requestIdFactory = _newRequestId,
    HomeApiClock clock = _utcNow,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration sendTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 15),
  }) : // The public named parameter intentionally differs from the private field.
       // ignore: prefer_initializing_formals
       _dio = dio,
       _endpoint = _homeEndpoint(baseUri),
       _timezone = _nonEmptyTimezone(timezone),
       // ignore: prefer_initializing_formals
       _requestIdFactory = requestIdFactory,
       // ignore: prefer_initializing_formals
       _clock = clock {
    _requireBoundedTimeout(connectTimeout, 'connectTimeout');
    _requireBoundedTimeout(sendTimeout, 'sendTimeout');
    _requireBoundedTimeout(receiveTimeout, 'receiveTimeout');
    _dio.options.connectTimeout = connectTimeout;
    _dio.options.sendTimeout = sendTimeout;
    _dio.options.receiveTimeout = receiveTimeout;
  }

  static const String _homePath = '/api/v1/home';
  static const String _correlationHeader = 'X-Correlation-ID';
  static const Duration _maximumTimeout = Duration(minutes: 1);
  static const int _maximumResponseBytes = 1024 * 1024;

  final Dio _dio;
  final Uri _endpoint;
  final String _timezone;
  final HomeRequestIdFactory _requestIdFactory;
  final HomeApiClock _clock;

  @override
  Future<HomeApiResult> fetchHome({String? etag, String? accessToken}) async {
    final correlationId = _safeGeneratedRequestId(_requestIdFactory);
    final normalizedEtag = _optionalHeaderValue(etag);
    if (etag != null && normalizedEtag == null) {
      return HomeApiOtherFailure(requestId: correlationId, statusCode: null);
    }

    final normalizedAccessToken = _optionalHeaderValue(
      accessToken,
      maximumLength: 8192,
    );
    if (accessToken != null && normalizedAccessToken == null) {
      return HomeApiOtherFailure(requestId: correlationId, statusCode: null);
    }

    final headers = <String, Object>{
      Headers.acceptHeader: Headers.jsonContentType,
      _correlationHeader: correlationId,
    };
    if (normalizedEtag != null) headers['If-None-Match'] = normalizedEtag;
    if (normalizedAccessToken != null) {
      headers['Authorization'] = 'Bearer $normalizedAccessToken';
    }

    try {
      final response = await _dio.get<Object?>(
        _endpoint.toString(),
        queryParameters: <String, Object>{
          'period': 'current_month',
          'timezone': _timezone,
        },
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
          followRedirects: false,
          maxRedirects: 0,
          receiveDataWhenStatusError: false,
          validateStatus: (status) => status == 200 || status == 304,
        ),
      );
      return _mapAcceptedResponse(response, correlationId);
    } on DioException catch (error) {
      return _mapDioFailure(error, correlationId);
    } on Object {
      return HomeApiOtherFailure(requestId: correlationId, statusCode: null);
    }
  }

  HomeApiResult _mapAcceptedResponse(
    Response<Object?> response,
    String correlationId,
  ) {
    final requestId = _responseRequestId(response.headers, correlationId);
    final responseEtag = _optionalHeaderValue(
      _firstHeader(response.headers, 'etag'),
    );

    if (response.statusCode == 304) {
      return HomeApiNotModified(requestId: requestId, etag: responseEtag);
    }
    if (response.statusCode != 200) {
      return HomeApiOtherFailure(
        requestId: requestId,
        statusCode: response.statusCode,
      );
    }

    try {
      final bytes = response.data;
      if (bytes is! List<int> ||
          bytes.isEmpty ||
          bytes.length > _maximumResponseBytes) {
        throw const FormatException('Invalid Home response size.');
      }
      final payload = _normalizePayload(
        jsonDecode(utf8.decode(bytes, allowMalformed: false)),
      );
      HomeDto.fromJson(payload);
      return HomeApiData(
        requestId: requestId,
        payload: payload,
        etag: responseEtag,
      );
    } on FormatException {
      return HomeApiMalformedFailure(requestId: requestId);
    } on TypeError {
      return HomeApiMalformedFailure(requestId: requestId);
    } on Object {
      return HomeApiMalformedFailure(requestId: requestId);
    }
  }

  HomeApiFailure _mapDioFailure(DioException error, String correlationId) {
    final response = error.response;
    final requestId = response == null
        ? correlationId
        : _responseRequestId(response.headers, correlationId);

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return HomeApiTimeoutFailure(requestId: requestId);
      case DioExceptionType.connectionError:
        return HomeApiOfflineFailure(requestId: requestId);
      case DioExceptionType.badResponse:
        return _mapHttpFailure(response, requestId);
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return HomeApiOtherFailure(requestId: requestId, statusCode: null);
    }
  }

  HomeApiFailure _mapHttpFailure(
    Response<Object?>? response,
    String requestId,
  ) {
    final statusCode = response?.statusCode;
    if (statusCode == 401) {
      return HomeApiUnauthorizedFailure(requestId: requestId);
    }
    if (statusCode == 408) {
      return HomeApiTimeoutFailure(requestId: requestId);
    }
    if (statusCode == 429) {
      return HomeApiThrottledFailure(
        requestId: requestId,
        retryAfter: _parseRetryAfter(
          response == null
              ? null
              : _firstHeader(response.headers, 'retry-after'),
          _clock().toUtc(),
        ),
      );
    }
    if (statusCode != null && statusCode >= 500 && statusCode <= 599) {
      return HomeApiServerFailure(requestId: requestId, statusCode: statusCode);
    }
    return HomeApiOtherFailure(requestId: requestId, statusCode: statusCode);
  }
}

Uri _homeEndpoint(Uri baseUri) {
  if (!baseUri.hasScheme || !baseUri.hasAuthority) {
    throw ArgumentError.value(baseUri, 'baseUri', 'Must be an absolute URI.');
  }
  if (baseUri.userInfo.isNotEmpty || baseUri.hasQuery || baseUri.hasFragment) {
    throw ArgumentError.value(
      baseUri,
      'baseUri',
      'Credentials, query parameters, and fragments are not allowed.',
    );
  }
  if (baseUri.scheme != 'https' &&
      !(baseUri.scheme == 'http' && _isLoopbackHost(baseUri.host))) {
    throw ArgumentError.value(
      baseUri,
      'baseUri',
      'HTTPS is required except for a loopback development endpoint.',
    );
  }
  return baseUri.resolve(HomeApi._homePath);
}

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

String _nonEmptyTimezone(String timezone) {
  final result = timezone.trim();
  if (result.isEmpty || result.length > 128 || _containsControl(result)) {
    throw ArgumentError.value(timezone, 'timezone', 'Must be a valid value.');
  }
  return result;
}

void _requireBoundedTimeout(Duration timeout, String name) {
  if (timeout <= Duration.zero || timeout > HomeApi._maximumTimeout) {
    throw ArgumentError.value(
      timeout,
      name,
      'Must be greater than zero and at most one minute.',
    );
  }
}

String? _optionalHeaderValue(String? value, {int maximumLength = 1024}) {
  if (value == null) return null;
  final result = value.trim();
  if (result.isEmpty ||
      result.length > maximumLength ||
      _containsControl(result)) {
    return null;
  }
  return result;
}

bool _containsControl(String value) {
  return value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);
}

String _responseRequestId(Headers headers, String fallback) {
  for (final name in const ['x-request-id', 'x-correlation-id']) {
    final candidate = _firstHeader(headers, name)?.trim();
    if (candidate != null &&
        RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(candidate)) {
      return candidate;
    }
  }
  return fallback;
}

String? _firstHeader(Headers headers, String name) {
  for (final entry in headers.map.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase() &&
        entry.value.isNotEmpty) {
      return entry.value.first;
    }
  }
  return null;
}

Map<String, Object?> _normalizePayload(Object? value) {
  final normalizer = _JsonNormalizer();
  final normalized = normalizer.normalize(value, depth: 0);
  if (normalized is! Map<String, Object?>) {
    throw const FormatException(r'$ must be an object.');
  }
  return normalized;
}

final class _JsonNormalizer {
  static const int _maximumDepth = 32;
  static const int _maximumNodes = 10000;

  int _nodes = 0;

  Object? normalize(Object? value, {required int depth}) {
    _nodes += 1;
    if (_nodes > _maximumNodes || depth > _maximumDepth) {
      throw const FormatException('JSON payload is too complex.');
    }
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const FormatException('JSON numbers must be finite.');
      }
      return value;
    }
    if (value is List<Object?>) {
      return List<Object?>.unmodifiable(
        value.map((item) => normalize(item, depth: depth + 1)),
      );
    }
    if (value is Map<Object?, Object?>) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FormatException('JSON object keys must be strings.');
        }
        result[key] = normalize(entry.value, depth: depth + 1);
      }
      return Map<String, Object?>.unmodifiable(result);
    }
    throw const FormatException('Unsupported JSON value.');
  }
}

Duration? _parseRetryAfter(String? rawValue, DateTime nowUtc) {
  if (rawValue == null) return null;
  final value = rawValue.trim();
  if (value.isEmpty || value.length > 128 || _containsControl(value)) {
    return null;
  }
  final seconds = int.tryParse(value);
  if (seconds != null &&
      seconds >= 0 &&
      seconds <= const Duration(days: 365).inSeconds) {
    return Duration(seconds: seconds);
  }

  final match = RegExp(
    r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) '
    r'(\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value);
  if (match == null) return null;
  const months = <String, int>{
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };
  final month = months[match.group(2)];
  if (month == null) return null;

  final day = int.parse(match.group(1)!);
  final year = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final retryAt = DateTime.utc(year, month, day, hour, minute, second);
  if (retryAt.year != year ||
      retryAt.month != month ||
      retryAt.day != day ||
      retryAt.hour != hour ||
      retryAt.minute != minute ||
      retryAt.second != second) {
    return null;
  }
  final delay = retryAt.difference(nowUtc);
  return delay.isNegative ? Duration.zero : delay;
}

String _safeGeneratedRequestId(HomeRequestIdFactory factory) {
  try {
    final candidate = factory();
    if (RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(candidate)) {
      return candidate;
    }
  } on Object {
    // Fall back to the local generator without exposing factory failures.
  }
  return _newRequestId();
}

String _newRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

DateTime _utcNow() => DateTime.now().toUtc();
