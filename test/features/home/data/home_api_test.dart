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
