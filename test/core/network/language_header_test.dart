import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/network/language_header.dart';

void main() {
  test('every request names the language current at that moment', () async {
    var language = 'de';
    final seen = <Object?>[];
    final dio = Dio()
      ..interceptors.add(LanguageHeaderInterceptor(() => language))
      ..httpClientAdapter = _Recording(seen);

    await dio.get<void>('https://example.test/first');
    language = 'uk';
    await dio.get<void>('https://example.test/second');

    expect(seen, ['de', 'uk']);
  });
}

class _Recording implements HttpClientAdapter {
  _Recording(this.seen);

  final List<Object?> seen;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options.headers['Accept-Language']);
    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {}
}
