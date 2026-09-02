import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/home/data/home_api.dart';

import '../../../support/home_contract_fixture.dart';

void main() {
  test('network client requests the versioned /api/v2/home endpoint', () async {
    final payload = jsonEncode(await loadHomeFixtureJson('populated.json'));
    final adapter = _RecordingAdapter(payload);
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final api = HomeApi(
      dio: dio,
      baseUri: Uri.parse('https://example.test/backend/'),
      timezone: 'Europe/Berlin',
      requestIdFactory: () => 'req_home_v2_test',
    );

    final result = await api.fetchHome(
      etag: '"home-v2"',
      accessToken: 'synthetic-access-token',
    );

    expect(result, isA<HomeApiData>());
    expect(adapter.requestedUri.path, '/api/v2/home');
    expect(adapter.requestedUri.path, isNot('/api/v1/home'));
    expect(adapter.requestedUri.queryParameters, {
      'period': 'current_month',
      'timezone': 'Europe/Berlin',
    });
    expect(adapter.method, 'GET');
  });

  // The zone is correctable (ADR 0028), so a client can be left behind by a
  // correction made elsewhere and would otherwise show an error until
  // something happened to read the account back.
  test('a timezone refusal names the zone to adopt', () async {
    final api = _apiRefusing(
      409,
      jsonEncode({
        'detail': {
          'code': 'CANONICAL_TIMEZONE_MISMATCH',
          'canonicalTimezone': 'Europe/Kyiv',
        },
      }),
    );

    final result = await api.fetchHome(accessToken: 'synthetic-access-token');

    expect(result, isA<HomeApiTimezoneMismatchFailure>());
    expect(
      (result as HomeApiTimezoneMismatchFailure).canonicalTimezone,
      'Europe/Kyiv',
    );
  });

  test('any other conflict stays an ordinary failure', () async {
    for (final body in const [
      '{"detail": {"code": "SOMETHING_ELSE"}}',
      '{"detail": {"code": "CANONICAL_TIMEZONE_MISMATCH"}}',
      '{"detail": {"code": "CANONICAL_TIMEZONE_MISMATCH",'
          ' "canonicalTimezone": "localtime"}}',
      'not json',
      '',
    ]) {
      final result = await _apiRefusing(
        409,
        body,
      ).fetchHome(accessToken: 'synthetic-access-token');

      expect(result, isA<HomeApiOtherFailure>(), reason: body);
    }
  });

  test('an error body is never mistaken for Home data', () async {
    final result = await _apiRefusing(
      503,
      '{"detail": "Home temporarily unavailable"}',
    ).fetchHome(accessToken: 'synthetic-access-token');

    expect(result, isA<HomeApiServerFailure>());
  });
}

HomeApi _apiRefusing(int statusCode, String body) {
  final dio = Dio()..httpClientAdapter = _RefusingAdapter(statusCode, body);
  addTearDown(() => dio.close(force: true));
  return HomeApi(
    dio: dio,
    baseUri: Uri.parse('https://example.test/backend/'),
    timezone: 'Europe/Lisbon',
    requestIdFactory: () => 'req_home_refusal_test',
  );
}

class _RefusingAdapter implements HttpClientAdapter {
  _RefusingAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        Headers.contentLengthHeader: [utf8.encode(body).length.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.payload);

  final String payload;
  late Uri requestedUri;
  late String method;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUri = options.uri;
    method = options.method;
    return ResponseBody.fromString(
      payload,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        Headers.contentLengthHeader: [utf8.encode(payload).length.toString()],
        'etag': ['"home-v2"'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
