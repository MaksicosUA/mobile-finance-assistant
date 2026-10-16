import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../home/data/home_session_store.dart';
import '../domain/auth_session.dart';

enum AuthFailureKind {
  invalidCredentials,
  emailInUse,
  invalidInput,
  invalidRefresh,
  throttled,
  offline,
  timeout,
  serviceUnavailable,
  malformedResponse,
  localStorage,
  unknown,
}

sealed class AuthSessionApiResult {
  const AuthSessionApiResult();
}

final class AuthSessionApiData extends AuthSessionApiResult {
  const AuthSessionApiData(this.tokens);

  final AuthTokenBundle tokens;
}

final class AuthSessionApiFailure extends AuthSessionApiResult {
  const AuthSessionApiFailure(this.kind);

  final AuthFailureKind kind;
}

abstract interface class AuthApiClient {
  Future<AuthSessionApiResult> register({
    required String displayName,
    required String email,
    required String password,
  });

  Future<AuthSessionApiResult> login({
    required String email,
    required String password,
  });

  Future<AuthSessionApiResult> refresh({required String refreshToken});

  Future<void> logout({required String refreshToken});
}

/// Strict, non-logging client for the native authentication endpoints.
final class AuthApi implements AuthApiClient {
  AuthApi({
    required Dio dio,
    required Uri baseUri,
    DateTime Function() clock = _utcNow,
    String Function() requestIdFactory = _newRequestId,
  }) : // Public dependency names intentionally differ from private fields.
       // ignore: prefer_initializing_formals
       _dio = dio,
       _baseUri = _validatedBaseUri(baseUri),
       // ignore: prefer_initializing_formals
       _clock = clock,
       // ignore: prefer_initializing_formals
       _requestIdFactory = requestIdFactory {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.sendTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
  }

  static const int _maximumResponseBytes = 64 * 1024;

  final Dio _dio;
  final Uri _baseUri;
  final DateTime Function() _clock;
  final String Function() _requestIdFactory;

  @override
  Future<AuthSessionApiResult> register({
    required String displayName,
    required String email,
    required String password,
  }) {
    final normalizedName = _displayName(displayName);
    final normalizedEmail = _email(email);
    if (normalizedName == null ||
        normalizedEmail == null ||
        !_validPassword(password)) {
      return Future.value(
        const AuthSessionApiFailure(AuthFailureKind.invalidInput),
      );
    }
    return _requestSession(
      path: '/api/v1/auth/register',
      operation: _AuthOperation.register,
      acceptedStatuses: const {201},
      body: <String, Object>{
        'displayName': normalizedName,
        'email': normalizedEmail,
        'password': password,
      },
    );
  }

  @override
  Future<AuthSessionApiResult> login({
    required String email,
    required String password,
  }) {
    final normalizedEmail = _email(email);
    if (normalizedEmail == null || !_validPassword(password)) {
      return Future.value(
        const AuthSessionApiFailure(AuthFailureKind.invalidInput),
      );
    }
    return _requestSession(
      path: '/api/v1/auth/login',
      operation: _AuthOperation.login,
      acceptedStatuses: const {200},
      body: <String, Object>{'email': normalizedEmail, 'password': password},
    );
  }

  @override
  Future<AuthSessionApiResult> refresh({required String refreshToken}) {
    final token = validSessionToken(refreshToken);
    if (token == null) {
      return Future.value(
        const AuthSessionApiFailure(AuthFailureKind.invalidRefresh),
      );
    }
    return _requestSession(
      path: '/api/v1/auth/refresh',
      operation: _AuthOperation.refresh,
      acceptedStatuses: const {200},
      body: <String, Object>{'refreshToken': token},
    );
  }

  @override
  Future<void> logout({required String refreshToken}) async {
    final token = validSessionToken(refreshToken);
    if (token == null) return;
    try {
      await _dio.post<Object?>(
        _baseUri.resolve('/api/v1/auth/logout').toString(),
        data: <String, Object>{'refreshToken': token},
        options: Options(
          headers: _headers(),
          responseType: ResponseType.bytes,
          followRedirects: false,
          maxRedirects: 0,
          receiveDataWhenStatusError: false,
          validateStatus: (status) => status == 200 || status == 204,
        ),
      );
    } on Object {
      // Logout is deliberately best-effort. Local credentials and encrypted
      // financial cache are still cleared by the repository.
    }
  }

  Future<AuthSessionApiResult> _requestSession({
    required String path,
    required _AuthOperation operation,
    required Set<int> acceptedStatuses,
    required Map<String, Object> body,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        _baseUri.resolve(path).toString(),
        data: body,
        options: Options(
          headers: _headers(),
          responseType: ResponseType.bytes,
          followRedirects: false,
          maxRedirects: 0,
          receiveDataWhenStatusError: false,
          validateStatus: acceptedStatuses.contains,
        ),
      );
      final bytes = response.data;
      if (bytes is! List<int> ||
          bytes.isEmpty ||
          bytes.length > _maximumResponseBytes) {
        return const AuthSessionApiFailure(AuthFailureKind.malformedResponse);
      }
      try {
        final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        if (decoded is! Map<String, Object?>) {
          throw const FormatException('Auth response must be an object.');
        }
        return AuthSessionApiData(_parseTokens(decoded));
      } on Object {
        return const AuthSessionApiFailure(AuthFailureKind.malformedResponse);
      }
    } on DioException catch (error) {
      return AuthSessionApiFailure(_mapFailure(error, operation));
    } on Object {
      return const AuthSessionApiFailure(AuthFailureKind.unknown);
    }
  }

  Map<String, Object> _headers() {
    return <String, Object>{
      Headers.acceptHeader: Headers.jsonContentType,
      Headers.contentTypeHeader: Headers.jsonContentType,
      'X-Correlation-ID': _safeRequestId(_requestIdFactory),
    };
  }

  AuthTokenBundle _parseTokens(Map<String, Object?> json) {
    final accessToken = json['accessToken'];
    final refreshToken = json['refreshToken'];
    final tokenType = json['tokenType'];
    final accessExpiresIn = json['accessExpiresIn'];
    final refreshExpiresIn = json['refreshExpiresIn'];
    final cacheScopeId = json['cacheScopeId'];
    final rawUser = json['user'];
    if (accessToken is! String ||
        refreshToken is! String ||
        tokenType != 'Bearer' ||
        accessExpiresIn is! int ||
        refreshExpiresIn is! int ||
        cacheScopeId is! String ||
        rawUser is! Map<String, Object?>) {
      throw const FormatException('Invalid authentication response.');
    }
    final userId = rawUser['id'];
    final displayName = rawUser['displayName'];
    final validAccess = validSessionToken(accessToken);
    final validRefresh = validSessionToken(refreshToken);
    final validScope = validCacheScopeId(cacheScopeId);
    if (validAccess == null ||
        validAccess != accessToken ||
        validRefresh == null ||
        validRefresh != refreshToken ||
        validScope == null ||
        validScope != cacheScopeId ||
        userId is! String ||
        userId != validScope ||
        displayName is! String ||
        _displayName(displayName) == null ||
        accessExpiresIn < 1 ||
        accessExpiresIn > const Duration(days: 1).inSeconds ||
        refreshExpiresIn <= accessExpiresIn ||
        refreshExpiresIn > const Duration(days: 366).inSeconds) {
      throw const FormatException('Invalid authentication response.');
    }
    final now = _clock().toUtc();
    return AuthTokenBundle(
      accessToken: validAccess,
      refreshToken: validRefresh,
      accessExpiresAtUtc: now.add(Duration(seconds: accessExpiresIn)),
      refreshExpiresAtUtc: now.add(Duration(seconds: refreshExpiresIn)),
      cacheScopeId: validScope,
      user: AuthUser(id: userId, displayName: displayName.trim()),
      // Added after this parser shipped, and read leniently on purpose: a
      // server that does not send it simply cancelled nothing.
      deletionCancelled: json['deletionCancelled'] == true,
    );
  }
}

enum _AuthOperation { register, login, refresh }

AuthFailureKind _mapFailure(DioException error, _AuthOperation operation) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return AuthFailureKind.timeout;
    case DioExceptionType.connectionError:
      return AuthFailureKind.offline;
    case DioExceptionType.badResponse:
      final status = error.response?.statusCode;
      if (status == 429) return AuthFailureKind.throttled;
      if (status != null && status >= 500) {
        return AuthFailureKind.serviceUnavailable;
      }
      if (operation == _AuthOperation.login && status == 401) {
        return AuthFailureKind.invalidCredentials;
      }
      if (operation == _AuthOperation.register && status == 409) {
        return AuthFailureKind.emailInUse;
      }
      if (operation == _AuthOperation.refresh &&
          (status == 401 || status == 409)) {
        return AuthFailureKind.invalidRefresh;
      }
      if (status == 400 || status == 401 || status == 409 || status == 422) {
        return AuthFailureKind.invalidInput;
      }
      return AuthFailureKind.unknown;
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return AuthFailureKind.unknown;
  }
}

Uri _validatedBaseUri(Uri value) {
  if (!value.hasScheme ||
      !value.hasAuthority ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment) {
    throw ArgumentError.value(value, 'baseUri', 'Invalid API base URI.');
  }
  if (value.scheme != 'https' &&
      !(value.scheme == 'http' && _isLoopback(value.host))) {
    throw ArgumentError.value(
      value,
      'baseUri',
      'HTTPS is required except for loopback development.',
    );
  }
  return value;
}

bool _isLoopback(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

String? _email(String value) {
  final result = value.trim().toLowerCase();
  if (result.isEmpty ||
      result.length > 254 ||
      result.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    return null;
  }
  final separator = result.indexOf('@');
  if (separator < 1 ||
      separator != result.lastIndexOf('@') ||
      separator == result.length - 1 ||
      !result.substring(separator + 1).contains('.')) {
    return null;
  }
  return result;
}

String? _displayName(String value) {
  final result = value.trim();
  if (result.isEmpty ||
      result.length > 100 ||
      result.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    return null;
  }
  return result;
}

bool _validPassword(String value) {
  final codePoints = value.runes.length;
  return codePoints >= 12 &&
      codePoints <= 128 &&
      utf8.encode(value).length <= 1024;
}

String _safeRequestId(String Function() factory) {
  try {
    final result = factory();
    if (RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(result)) return result;
  } on Object {
    // Fall through to a local random correlation ID.
  }
  return _newRequestId();
}

String _newRequestId() {
  final random = Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

DateTime _utcNow() => DateTime.now().toUtc();
