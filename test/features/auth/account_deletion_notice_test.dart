import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/auth/application/auth_controller.dart';
import 'package:mobile_finance_assistant/features/auth/data/auth_api.dart';
import 'package:mobile_finance_assistant/features/auth/data/auth_repository.dart';
import 'package:mobile_finance_assistant/features/auth/data/auth_session_store.dart';
import 'package:mobile_finance_assistant/features/auth/domain/auth_session.dart';
import 'package:mobile_finance_assistant/features/auth/presentation/auth_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

/// What signing in and out says about a scheduled erasure (ADR 0030).
void main() {
  group('the sign-in answer', () {
    test('says when it cancelled a scheduled erasure', () async {
      final tokens = await _login({..._tokenJson, 'deletionCancelled': true});
      expect(tokens.deletionCancelled, isTrue);
    });

    test('from a server that predates erasure cancels nothing', () async {
      final tokens = await _login(_tokenJson);
      expect(tokens.deletionCancelled, isFalse);
    });

    test('reads anything but true as nothing cancelled', () async {
      final tokens = await _login({..._tokenJson, 'deletionCancelled': 'yes'});
      expect(tokens.deletionCancelled, isFalse);
    });
  });

  group('the auth controller', () {
    test('a sign-in that cancelled an erasure says so once in', () async {
      final store = _FakeStore();
      final container = _container(
        _FakeApi(_bundle(deletionCancelled: true)),
        store,
      );
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .login(email: 'owner@example.test', password: 'synthetic-password');

      final state = container.read(authControllerProvider);
      expect((state as AuthSignedIn).notice, AuthNotice.deletionCancelled);
    });

    test('an ordinary sign-in says nothing', () async {
      final container = _container(_FakeApi(_bundle()), _FakeStore());
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .login(email: 'owner@example.test', password: 'synthetic-password');

      final state = container.read(authControllerProvider);
      expect((state as AuthSignedIn).notice, AuthNotice.none);
    });

    test('a scheduled erasure drops the local session and says when', () async {
      final store = _FakeStore();
      final api = _FakeApi(_bundle());
      final container = _container(api, store);
      addTearDown(container.dispose);
      final dueAt = DateTime.utc(2026, 10, 23, 12);

      await container
          .read(authControllerProvider.notifier)
          .accountDeletionScheduled(dueAt);

      final state = container.read(authControllerProvider) as AuthSignedOut;
      expect(state.notice, AuthNotice.deletionScheduled);
      expect(state.deletionDueAt, dueAt);
      expect(store.cleared, 1);
      // The server already ended every session; there is nothing to revoke.
      expect(api.logouts, 0);
    });
  });

  testWidgets('the sign-in page says the date the erasure is due', (
    tester,
  ) async {
    await _pumpAuthPage(
      tester,
      AuthPage(
        mode: AuthMode.login,
        notice: AuthNotice.deletionScheduled,
        deletionDueAt: DateTime.utc(2026, 10, 23, 12),
      ),
    );

    expect(find.textContaining('23 октября 2026'), findsOneWidget);
    expect(find.textContaining('просто войдите'), findsOneWidget);
  });

  testWidgets('without a date it still says how to cancel', (tester) async {
    await _pumpAuthPage(
      tester,
      const AuthPage(
        mode: AuthMode.login,
        notice: AuthNotice.deletionScheduled,
      ),
    );

    expect(find.textContaining('через 7 дней'), findsOneWidget);
  });
}

Future<void> _pumpAuthPage(WidgetTester tester, AuthPage page) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(AppAccent.teal),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _userId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

const _tokenJson = <String, Object?>{
  'accessToken': 'synthetic-access-token',
  'refreshToken': 'synthetic-refresh-token',
  'tokenType': 'Bearer',
  'accessExpiresIn': 900,
  'refreshExpiresIn': 2592000,
  'cacheScopeId': _userId,
  'user': {'id': _userId, 'displayName': 'Синтетический Пользователь'},
};

Future<AuthTokenBundle> _login(Map<String, Object?> json) async {
  final dio = Dio()..httpClientAdapter = _OneResponse(json);
  addTearDown(() => dio.close(force: true));
  final api = AuthApi(
    dio: dio,
    baseUri: Uri.parse('https://example.test/'),
    clock: () => DateTime.utc(2026, 10, 16, 12),
  );
  final result = await api.login(
    email: 'owner@example.test',
    password: 'synthetic-password',
  );
  return (result as AuthSessionApiData).tokens;
}

AuthTokenBundle _bundle({bool deletionCancelled = false}) => AuthTokenBundle(
  accessToken: 'synthetic-access-token',
  refreshToken: 'synthetic-refresh-token',
  accessExpiresAtUtc: DateTime.utc(2026, 10, 16, 12, 15),
  refreshExpiresAtUtc: DateTime.utc(2026, 11, 15, 12),
  cacheScopeId: _userId,
  user: const AuthUser(id: _userId, displayName: 'Синтетический Пользователь'),
  deletionCancelled: deletionCancelled,
);

ProviderContainer _container(_FakeApi api, _FakeStore store) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        AuthRepository(api: api, sessionStore: store),
      ),
    ],
  );
}

final class _FakeApi implements AuthApiClient {
  _FakeApi(this._tokens);

  final AuthTokenBundle _tokens;
  int logouts = 0;

  @override
  Future<AuthSessionApiResult> login({
    required String email,
    required String password,
  }) async => AuthSessionApiData(_tokens);

  @override
  Future<void> logout({required String refreshToken}) async {
    logouts += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeStore implements AuthSessionStore {
  int cleared = 0;

  @override
  Future<AuthSession> saveAuthenticatedSession(AuthTokenBundle tokens) async {
    return AuthSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAtUtc: tokens.accessExpiresAtUtc,
      refreshExpiresAtUtc: tokens.refreshExpiresAtUtc,
      cacheScopeId: tokens.cacheScopeId,
      revision: '0123456789abcdef0123456789abcdef',
    );
  }

  @override
  Future<void> clearSession() async {
    cleared += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _OneResponse implements HttpClientAdapter {
  _OneResponse(this._json);

  final Map<String, Object?> _json;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode(_json);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        Headers.contentLengthHeader: [utf8.encode(body).length.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
