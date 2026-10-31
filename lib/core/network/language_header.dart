import 'package:dio/dio.dart';

/// Tells the server which language the app is in.
///
/// Read on every request rather than fixed when the client is built, because
/// the language can change while the client lives. The server uses it once, to
/// write a new account's catalogue (ADR 0034).
class LanguageHeaderInterceptor extends Interceptor {
  LanguageHeaderInterceptor(this._languageCode);

  final String Function() _languageCode;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Accept-Language'] = _languageCode();
    handler.next(options);
  }
}
