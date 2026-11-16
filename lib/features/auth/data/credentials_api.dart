import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../home/data/home_session_store.dart';
import '../domain/recovery_code.dart';

/// Why a request about a password or a recovery code did not go through.
enum CredentialFailureKind {
  /// The password given to confirm the request did not match.
  passwordRejected,

  /// The new password is outside what the server accepts.
  newPasswordRejected,

  /// The address and code did not open an account. Which of them, the server
  /// does not say, and neither does the app.
  recoveryRejected,

  /// The session has ended; signing in again is the way back.
  authenticationRequired,
  throttled,
  invalidInput,
  offline,
  timeout,

  /// The server answered and could not do it, or does not know the route yet.
  unavailable,
  malformedResponse,
  unknown,
}

sealed class CredentialResult<T> {
  const CredentialResult();
}

final class CredentialSuccess<T> extends CredentialResult<T> {
  const CredentialSuccess(this.value);

  final T value;
}

final class CredentialFailure<T> extends CredentialResult<T> {
  const CredentialFailure(this.kind);

  final CredentialFailureKind kind;
}

abstract interface class CredentialsApiClient {
  Future<CredentialResult<RecoveryCodeStatus>> readRecoveryCodeStatus({
    required String accessToken,
  });

  Future<CredentialResult<RecoveryCode>> issueRecoveryCode({
    required String accessToken,
    required String password,
  });

  Future<CredentialResult<void>> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  });

  Future<CredentialResult<RecoveryCode>> resetPassword({
    required String email,
    required String recoveryCode,
    required String newPassword,
  });
}

/// Strict, non-logging client for changing and recovering a password
/// (ADR 0035). Nothing here is retried: a password is asked of a person once.
final class CredentialsApi implements CredentialsApiClient {
  CredentialsApi({
    required Dio dio,
    required Uri baseUri,
    String Function() requestIdFactory = _newRequestId,
  }) : // Public dependency names intentionally differ from private fields.
       // ignore: prefer_initializing_formals
       _dio = dio,
       // ignore: prefer_initializing_formals
       _baseUri = baseUri,
       // ignore: prefer_initializing_formals
       _requestIdFactory = requestIdFactory {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.sendTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
  }

  static const int _maximumResponseBytes = 16 * 1024;
  static const String _statusPath = '/api/v1/auth/recovery-code';

  final Dio _dio;
  final Uri _baseUri;
  final String Function() _requestIdFactory;

  @override
  Future<CredentialResult<RecoveryCodeStatus>> readRecoveryCodeStatus({
    required String accessToken,
  }) {
    return _send(
      method: 'GET',
      path: _statusPath,
      accessToken: accessToken,
      accepted: 200,
      parse: _parseStatus,
    );
  }

  @override
  Future<CredentialResult<RecoveryCode>> issueRecoveryCode({
    required String accessToken,
    required String password,
  }) {
    return _send(
      method: 'POST',
      path: _statusPath,
      accessToken: accessToken,
      accepted: 201,
      body: <String, Object>{'schemaVersion': '1', 'password': password},
      parse: _parseCode,
    );
  }

  @override
  Future<CredentialResult<void>> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) {
    return _send<void>(
      method: 'POST',
      path: '/api/v1/auth/password/change',
      accessToken: accessToken,
      accepted: 204,
      body: <String, Object>{
        'schemaVersion': '1',
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      parse: null,
    );
  }

  @override
  Future<CredentialResult<RecoveryCode>> resetPassword({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) {
    final canonical = canonicalRecoveryCode(recoveryCode);
    final address = email.trim();
    if (canonical == null || address.isEmpty) {
      return Future.value(
        const CredentialFailure(CredentialFailureKind.invalidInput),
      );
    }
    return _send(
      method: 'POST',
      path: '/api/v1/auth/password/reset',
      accepted: 200,
      body: <String, Object>{
        'schemaVersion': '1',
        'email': address,
        'recoveryCode': canonical,
        'newPassword': newPassword,
      },
      parse: _parseCode,
    );
  }

  /// One request, one answer. [accessToken] is absent only for the reset,
  /// which is for someone who cannot sign in.
  Future<CredentialResult<T>> _send<T>({
    required String method,
    required String path,
    required int accepted,
    required T Function(Map<String, Object?> json)? parse,
    String? accessToken,
    Map<String, Object>? body,
  }) async {
    final signedIn = accessToken != null;
    final token = signedIn ? validSessionToken(accessToken) : null;
    if (signedIn && token == null) {
      return const CredentialFailure(
        CredentialFailureKind.authenticationRequired,
      );
    }
    try {
      final response = await _dio.request<Object?>(
        _baseUri.resolve(path).toString(),
        data: body,
        options: Options(
          method: method,
          headers: <String, Object>{
            Headers.acceptHeader: Headers.jsonContentType,
            if (body != null)
              Headers.contentTypeHeader: Headers.jsonContentType,
            if (token != null) 'Authorization': 'Bearer $token',
            'X-Correlation-ID': _safeRequestId(_requestIdFactory),
          },
          responseType: ResponseType.bytes,
          followRedirects: false,
          maxRedirects: 0,
          receiveDataWhenStatusError: true,
          validateStatus: (status) => status != null,
        ),
      );
      final status = response.statusCode;
      final bytes = response.data;
      if (status != accepted) {
        return CredentialFailure(
          _refusal(status, _errorCode(bytes), signedIn: signedIn),
        );
      }
      if (parse == null) return CredentialSuccess<T>(null as T);
      if (bytes is! List<int> ||
          bytes.isEmpty ||
          bytes.length > _maximumResponseBytes) {
        return const CredentialFailure(CredentialFailureKind.malformedResponse);
      }
      try {
        final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        if (decoded is! Map<String, Object?>) {
          throw const FormatException('The answer must be an object.');
        }
        return CredentialSuccess(parse(decoded));
      } on Object {
        return const CredentialFailure(CredentialFailureKind.malformedResponse);
      }
    } on DioException catch (error) {
      return CredentialFailure(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.transformTimeout => CredentialFailureKind.timeout,
        DioExceptionType.connectionError => CredentialFailureKind.offline,
        _ => CredentialFailureKind.unknown,
      });
    } on Object {
      return const CredentialFailure(CredentialFailureKind.unknown);
    }
  }
}

CredentialFailureKind _refusal(
  int? status,
  String? code, {
  required bool signedIn,
}) {
  return switch (status) {
    // Only a signed-in request can have lost its session. The reset opens
    // none, so a 401 there is not something this client knows how to read.
    401 when signedIn => CredentialFailureKind.authenticationRequired,
    // A wrong password is a refusal of this request, not of the session,
    // which is why the server answers 403 and never 401.
    403 when code == 'PASSWORD_REJECTED' =>
      CredentialFailureKind.passwordRejected,
    403 when code == 'RECOVERY_REJECTED' =>
      CredentialFailureKind.recoveryRejected,
    400 when code == 'NEW_PASSWORD_REJECTED' =>
      CredentialFailureKind.newPasswordRejected,
    422 => CredentialFailureKind.invalidInput,
    429 => CredentialFailureKind.throttled,
    // A server that predates recovery codes does not have the route.
    404 => CredentialFailureKind.unavailable,
    final int value when value >= 500 => CredentialFailureKind.unavailable,
    _ => CredentialFailureKind.unknown,
  };
}

String? _errorCode(Object? bytes) {
  if (bytes is! List<int> || bytes.isEmpty || bytes.length > 4096) return null;
  try {
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map<String, Object?>) return null;
    final detail = decoded['detail'];
    if (detail is! Map<String, Object?>) return null;
    final code = detail['code'];
    return code is String ? code : null;
  } on Object {
    return null;
  }
}

RecoveryCodeStatus _parseStatus(Map<String, Object?> json) {
  final exists = json['exists'];
  final createdAt = json['createdAt'];
  if (json['schemaVersion'] != '1' || exists is! bool) {
    throw const FormatException('Invalid recovery code status.');
  }
  final created = createdAt == null ? null : _utc(createdAt);
  // A code and the day it was made exist together or not at all.
  if (exists != (created != null)) {
    throw const FormatException('Invalid recovery code status.');
  }
  return RecoveryCodeStatus(exists: exists, createdAtUtc: created);
}

RecoveryCode _parseCode(Map<String, Object?> json) {
  final value = json['recoveryCode'];
  if (json['schemaVersion'] != '1' ||
      value is! String ||
      // Anything else on the screen would be copied down as if it were a code.
      !isIssuedRecoveryCode(value)) {
    throw const FormatException('Invalid recovery code.');
  }
  return RecoveryCode(value: value, createdAtUtc: _utc(json['createdAt']));
}

DateTime _utc(Object? value) {
  if (value is! String) throw const FormatException('Invalid timestamp.');
  final parsed = DateTime.parse(value);
  if (!parsed.isUtc) throw const FormatException('Timestamp must be UTC.');
  return parsed;
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
