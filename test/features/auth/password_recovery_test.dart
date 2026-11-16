import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/auth/application/auth_controller.dart';
import 'package:mobile_finance_assistant/features/auth/application/credentials_controller.dart';
import 'package:mobile_finance_assistant/features/auth/data/auth_api.dart';
import 'package:mobile_finance_assistant/features/auth/data/auth_repository.dart';
import 'package:mobile_finance_assistant/features/auth/data/auth_session_store.dart';
import 'package:mobile_finance_assistant/features/auth/data/credentials_api.dart';
import 'package:mobile_finance_assistant/features/auth/data/credentials_repository.dart';
import 'package:mobile_finance_assistant/features/auth/domain/auth_session.dart';
import 'package:mobile_finance_assistant/features/auth/domain/recovery_code.dart';
import 'package:mobile_finance_assistant/features/auth/presentation/auth_gate.dart';
import 'package:mobile_finance_assistant/features/auth/presentation/auth_page.dart';
import 'package:mobile_finance_assistant/features/auth/presentation/credentials_section.dart';
import 'package:mobile_finance_assistant/features/auth/presentation/password_change_page.dart';
import 'package:mobile_finance_assistant/features/auth/presentation/recovery_code_issue_page.dart';
import 'package:mobile_finance_assistant/features/auth/presentation/recovery_code_page.dart';
import 'package:mobile_finance_assistant/features/voice_entry/data/waiting_phrase_store.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

/// Getting back in without the password, and changing it (ADR 0035).
void main() {
  group('a recovery code as a person types it', () {
    for (final typed in [
      'ABCDE-FGHJK-MNPQR-STVWX',
      'abcde-fghjk-mnpqr-stvwx',
      'ABCDEFGHJKMNPQRSTVWX',
      'abcde fghjk mnpqr stvwx',
      '  ABCDE-FGHJK-MNPQR-STVWX\n',
      // What a phone keyboard puts where a hyphen was meant.
      'ABCDE${String.fromCharCode(0x2013)}FGHJK${String.fromCharCode(0x2014)}'
          'MNPQR${String.fromCharCode(0x2212)}STVWX',
    ]) {
      test('reads "${typed.trim()}" as the same code', () {
        expect(canonicalRecoveryCode(typed), 'ABCDEFGHJKMNPQRSTVWX');
      });
    }

    test(
      'reads a letter the alphabet leaves out as the digit it looks like',
      () {
        expect(
          canonicalRecoveryCode('oil00-00000-00000-00000'),
          '01100000000000000000',
        );
      },
    );

    for (final (label, text) in [
      ('nothing', ''),
      ('one character short', 'ABCDE-FGHJK-MNPQR-STVW'),
      ('one character long', 'ABCDE-FGHJK-MNPQR-STVWX0'),
      ('a letter no code has', 'ABCDE-FGHJK-MNPQR-STVWU'),
      ('punctuation', 'ABCDE-FGHJK-MNPQR-STVW!'),
      // Cyrillic А, В and С look like the Latin ones and are not.
      (
        'look-alike letters',
        '${String.fromCharCodes([0x410, 0x412, 0x421])}DE-FGHJK-MNPQR-STVWX',
      ),
    ]) {
      test('refuses $label before anything is sent', () {
        expect(canonicalRecoveryCode(text), isNull);
      });
    }

    test('only what the server writes counts as an issued code', () {
      expect(isIssuedRecoveryCode(_code), isTrue);
      expect(isIssuedRecoveryCode('ABCDEFGHJKMNPQRSTVWX'), isFalse);
      expect(isIssuedRecoveryCode('abcde-fghjk-mnpqr-stvwx'), isFalse);
      expect(isIssuedRecoveryCode('<b>ABCDE-FGHJK-MNPQR-STVWX'), isFalse);
    });
  });

  group('the requests', () {
    test(
      'a reset goes without a session and carries the code as one',
      () async {
        final adapter = _Recording(200, _codeJson(_nextCode));
        final result = await _api(adapter).resetPassword(
          email: '  owner@example.test ',
          recoveryCode: 'abcde fghjk-mnpqr stvwx',
          newPassword: _newPassword,
        );

        expect(
          (result as CredentialSuccess<RecoveryCode>).value.value,
          _nextCode,
        );
        final request = adapter.requests.single;
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/auth/password/reset');
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.data, {
          'schemaVersion': '1',
          'email': 'owner@example.test',
          'recoveryCode': 'ABCDEFGHJKMNPQRSTVWX',
          'newPassword': _newPassword,
        });
      },
    );

    test('text that cannot be a code is not sent at all', () async {
      final adapter = _Recording(200, _codeJson(_nextCode));
      final result = await _api(adapter).resetPassword(
        email: 'owner@example.test',
        recoveryCode: 'not a code',
        newPassword: _newPassword,
      );

      expect(_kind(result), CredentialFailureKind.invalidInput);
      expect(adapter.requests, isEmpty);
    });

    for (final (status, code, kind) in [
      (403, 'RECOVERY_REJECTED', CredentialFailureKind.recoveryRejected),
      (400, 'NEW_PASSWORD_REJECTED', CredentialFailureKind.newPasswordRejected),
      (422, 'MALFORMED_CREDENTIAL_REQUEST', CredentialFailureKind.invalidInput),
      (429, null, CredentialFailureKind.throttled),
      // A server that predates recovery codes.
      (404, null, CredentialFailureKind.unavailable),
      (503, 'CREDENTIALS_UNAVAILABLE', CredentialFailureKind.unavailable),
      // A reset opens no session, so it has none to lose.
      (401, null, CredentialFailureKind.unknown),
    ]) {
      test('a reset answered $status ${code ?? ''} is $kind', () async {
        final adapter = _Recording(status, _errorJson(code));
        final result = await _api(adapter).resetPassword(
          email: 'owner@example.test',
          recoveryCode: _code,
          newPassword: _newPassword,
        );
        expect(_kind(result), kind);
      });
    }

    test('a new code is asked for with the session and the password', () async {
      final adapter = _Recording(201, _codeJson(_code));
      final result = await _api(
        adapter,
      ).issueRecoveryCode(accessToken: 'synthetic-access', password: _password);

      expect((result as CredentialSuccess<RecoveryCode>).value.value, _code);
      final request = adapter.requests.single;
      expect(request.uri.path, '/api/v1/auth/recovery-code');
      expect(request.headers['Authorization'], 'Bearer synthetic-access');
      expect(request.data, {'schemaVersion': '1', 'password': _password});
    });

    test('a wrong password is not a lost session', () async {
      final wrong = await _api(
        _Recording(403, _errorJson('PASSWORD_REJECTED')),
      ).issueRecoveryCode(accessToken: 'synthetic-access', password: _password);
      final expired = await _api(
        _Recording(401, null),
      ).issueRecoveryCode(accessToken: 'synthetic-access', password: _password);

      expect(_kind(wrong), CredentialFailureKind.passwordRejected);
      expect(_kind(expired), CredentialFailureKind.authenticationRequired);
    });

    for (final (label, json) in [
      ('no code', <String, Object?>{'schemaVersion': '1', 'createdAt': _at}),
      ('a code without its hyphens', _codeJson('ABCDEFGHJKMNPQRSTVWX')),
      ('words where the code should be', _codeJson('Ошибка сервера')),
      ('another schema', {..._codeJson(_code), 'schemaVersion': '2'}),
      (
        'no date',
        <String, Object?>{'schemaVersion': '1', 'recoveryCode': _code},
      ),
    ]) {
      test('an answer with $label is never shown as a code', () async {
        final result = await _api(_Recording(201, json)).issueRecoveryCode(
          accessToken: 'synthetic-access',
          password: _password,
        );
        expect(_kind(result), CredentialFailureKind.malformedResponse);
      });
    }

    test('the status says whether there is a code, and since when', () async {
      final has = await _api(
        _Recording(200, {
          'schemaVersion': '1',
          'exists': true,
          'createdAt': _at,
        }),
      ).readRecoveryCodeStatus(accessToken: 'synthetic-access');
      final none = await _api(
        _Recording(200, {
          'schemaVersion': '1',
          'exists': false,
          'createdAt': null,
        }),
      ).readRecoveryCodeStatus(accessToken: 'synthetic-access');
      final contradictory = await _api(
        _Recording(200, {
          'schemaVersion': '1',
          'exists': true,
          'createdAt': null,
        }),
      ).readRecoveryCodeStatus(accessToken: 'synthetic-access');

      final status = (has as CredentialSuccess<RecoveryCodeStatus>).value;
      expect(status.exists, isTrue);
      expect(status.createdAtUtc, DateTime.utc(2026, 11, 16, 9, 30));
      expect(
        (none as CredentialSuccess<RecoveryCodeStatus>).value.exists,
        isFalse,
      );
      expect(_kind(contradictory), CredentialFailureKind.malformedResponse);
    });

    test('a changed password is an answer with nothing in it', () async {
      final adapter = _Recording(204, null);
      final result = await _api(adapter).changePassword(
        accessToken: 'synthetic-access',
        currentPassword: _password,
        newPassword: _newPassword,
      );

      expect(result, isA<CredentialSuccess<void>>());
      expect(adapter.requests.single.uri.path, '/api/v1/auth/password/change');
      expect(adapter.requests.single.data, {
        'schemaVersion': '1',
        'currentPassword': _password,
        'newPassword': _newPassword,
      });
    });
  });

  group('the session a request goes out on', () {
    test('nobody signed in means nothing is sent', () async {
      final api = _FakeCredentialsApi();
      final repository = CredentialsRepository(
        api: api,
        auth: AuthRepository(api: _FakeAuthApi(), sessionStore: _FakeStore()),
      );

      final result = await repository.issueRecoveryCode(password: _password);

      expect(_kind(result), CredentialFailureKind.authenticationRequired);
      expect(api.tokens, isEmpty);
    });

    test('a fresh token is used as it is', () async {
      final api = _FakeCredentialsApi();
      final store = _FakeStore()
        ..session = _session('fresh-access', minutes: 9);
      final repository = CredentialsRepository(
        api: api,
        auth: AuthRepository(
          api: _FakeAuthApi(),
          sessionStore: store,
          clock: () => _now,
        ),
      );

      await repository.issueRecoveryCode(password: _password);

      expect(api.tokens, ['fresh-access']);
    });

    test('a token about to expire is renewed first', () async {
      final api = _FakeCredentialsApi();
      final store = _FakeStore()
        ..session = _session('stale-access', minutes: 0);
      final auth = _FakeAuthApi()
        ..refreshed = _bundle(accessToken: 'renewed-access');
      final repository = CredentialsRepository(
        api: api,
        auth: AuthRepository(api: auth, sessionStore: store, clock: () => _now),
      );

      await repository.changePassword(
        currentPassword: _password,
        newPassword: _newPassword,
      );

      expect(api.tokens, ['renewed-access']);
    });

    test('a session that cannot be renewed has ended', () async {
      final api = _FakeCredentialsApi();
      final store = _FakeStore()
        ..session = _session('stale-access', minutes: 0);
      final repository = CredentialsRepository(
        api: api,
        auth: AuthRepository(
          api: _FakeAuthApi(),
          sessionStore: store,
          clock: () => _now,
        ),
      );

      final result = await repository.readRecoveryCodeStatus();

      expect(_kind(result), CredentialFailureKind.authenticationRequired);
      expect(api.tokens, isEmpty);
    });

    test('a reset needs no session at all', () async {
      final api = _FakeCredentialsApi();
      final repository = CredentialsRepository(
        api: api,
        auth: AuthRepository(api: _FakeAuthApi(), sessionStore: _FakeStore()),
      );

      final result = await repository.resetPassword(
        email: 'owner@example.test',
        recoveryCode: _code,
        newPassword: _newPassword,
      );

      expect(result, isA<CredentialSuccess<RecoveryCode>>());
    });
  });

  group('creating an account', () {
    test('ends with a recovery code waiting to be kept', () async {
      final credentials = _FakeCredentials();
      final container = _container(credentials: credentials);
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .register(
            displayName: 'Синтетический',
            email: 'owner@example.test',
            password: _password,
          );

      expect(container.read(authControllerProvider), isA<AuthSignedIn>());
      // Asked for with the password that was just chosen, not a second prompt.
      expect(credentials.issued, [_password]);
      expect(container.read(pendingRecoveryCodeProvider)?.value, _code);
    });

    test('still succeeds when the code could not be issued', () async {
      final credentials = _FakeCredentials()
        ..issue = const CredentialFailure(CredentialFailureKind.offline);
      final container = _container(credentials: credentials);
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .register(
            displayName: 'Синтетический',
            email: 'owner@example.test',
            password: _password,
          );

      expect(container.read(authControllerProvider), isA<AuthSignedIn>());
      expect(container.read(pendingRecoveryCodeProvider), isNull);
    });

    test('that was refused asks for no code', () async {
      final credentials = _FakeCredentials();
      final container = _container(
        credentials: credentials,
        auth: _FakeAuthApi()..registerFailure = AuthFailureKind.emailInUse,
      );
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .register(
            displayName: 'Синтетический',
            email: 'owner@example.test',
            password: _password,
          );

      final state = container.read(authControllerProvider) as AuthSignedOut;
      expect(state.issue, AuthFailureKind.emailInUse);
      expect(credentials.issued, isEmpty);
      expect(container.read(pendingRecoveryCodeProvider), isNull);
    });

    test('signing in asks for no code', () async {
      final credentials = _FakeCredentials();
      final container = _container(credentials: credentials);
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .login(email: 'owner@example.test', password: _password);

      expect(container.read(authControllerProvider), isA<AuthSignedIn>());
      expect(credentials.issued, isEmpty);
      expect(container.read(pendingRecoveryCodeProvider), isNull);
    });
  });

  group('a forgotten password', () {
    test(
      'is replaced, then the person is signed in with the new one',
      () async {
        final credentials = _FakeCredentials();
        final auth = _FakeAuthApi();
        final container = _container(credentials: credentials, auth: auth);
        addTearDown(container.dispose);

        await container
            .read(authControllerProvider.notifier)
            .resetPassword(
              email: 'owner@example.test',
              recoveryCode: _code,
              newPassword: _newPassword,
            );

        expect(credentials.resets, [
          ('owner@example.test', _code, _newPassword),
        ]);
        expect(auth.logins, [('owner@example.test', _newPassword)]);
        expect(container.read(authControllerProvider), isA<AuthSignedIn>());
        // The code that was used is spent; this is the one to keep now.
        expect(container.read(pendingRecoveryCodeProvider)?.value, _nextCode);
      },
    );

    test(
      'hands over the next code even when the sign-in after it failed',
      () async {
        final container = _container(
          credentials: _FakeCredentials(),
          auth: _FakeAuthApi()..loginFailure = AuthFailureKind.offline,
        );
        addTearDown(container.dispose);

        await container
            .read(authControllerProvider.notifier)
            .resetPassword(
              email: 'owner@example.test',
              recoveryCode: _code,
              newPassword: _newPassword,
            );

        final state = container.read(authControllerProvider) as AuthSignedOut;
        expect(state.mode, AuthMode.login);
        expect(state.notice, AuthNotice.passwordReset);
        // Dropping it would leave an account with a new password and no way
        // back in: the old code is spent and this exists nowhere else.
        expect(container.read(pendingRecoveryCodeProvider)?.value, _nextCode);
      },
    );

    test('that was refused stays on the form and signs nobody in', () async {
      final auth = _FakeAuthApi();
      final container = _container(
        credentials: _FakeCredentials()
          ..reset = const CredentialFailure(
            CredentialFailureKind.recoveryRejected,
          ),
        auth: auth,
      );
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .resetPassword(
            email: 'owner@example.test',
            recoveryCode: _code,
            newPassword: _newPassword,
          );

      final state = container.read(authControllerProvider) as AuthSignedOut;
      expect(state.mode, AuthMode.recover);
      expect(state.issue, AuthFailureKind.recoveryRejected);
      expect(auth.logins, isEmpty);
      expect(container.read(pendingRecoveryCodeProvider), isNull);
    });

    for (final (kind, issue) in [
      (CredentialFailureKind.throttled, AuthFailureKind.throttled),
      (CredentialFailureKind.offline, AuthFailureKind.offline),
      (CredentialFailureKind.timeout, AuthFailureKind.timeout),
      (CredentialFailureKind.unavailable, AuthFailureKind.serviceUnavailable),
      (CredentialFailureKind.newPasswordRejected, AuthFailureKind.invalidInput),
    ]) {
      test('says $issue when the reset answered $kind', () async {
        final container = _container(
          credentials: _FakeCredentials()..reset = CredentialFailure(kind),
        );
        addTearDown(container.dispose);

        await container
            .read(authControllerProvider.notifier)
            .resetPassword(
              email: 'owner@example.test',
              recoveryCode: _code,
              newPassword: _newPassword,
            );

        final state = container.read(authControllerProvider) as AuthSignedOut;
        expect(state.issue, issue);
      });
    }
  });

  test('a code on screen is protected whatever the privacy setting says', () {
    expect(
      screenIsProtected(
        signedIn: true,
        privacyMode: false,
        recoveryCodeOnScreen: true,
      ),
      isTrue,
    );
    expect(
      screenIsProtected(
        signedIn: true,
        privacyMode: false,
        recoveryCodeOnScreen: false,
      ),
      isFalse,
    );
    expect(
      screenIsProtected(
        signedIn: true,
        privacyMode: true,
        recoveryCodeOnScreen: false,
      ),
      isTrue,
    );
    expect(
      screenIsProtected(
        signedIn: false,
        privacyMode: false,
        recoveryCodeOnScreen: false,
      ),
      isTrue,
    );
  });

  group('on screen', () {
    testWidgets('a forgotten password is replaced from the sign-in page', (
      tester,
    ) async {
      final credentials = _FakeCredentials();
      final auth = _FakeAuthApi();
      final container = await _pump(
        tester,
        const _Host(),
        credentials: credentials,
        auth: auth,
      );
      container.read(authControllerProvider.notifier).showMode(AuthMode.login);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-recovery-code')), findsNothing);
      await tester.tap(find.byKey(const Key('auth-forgot-password')));
      await tester.pumpAndSettle();
      expect(find.text('Новый пароль'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('auth-email')),
        'owner@example.test',
      );
      // A code that cannot be one is caught on the phone, not spent on the
      // server.
      await tester.enterText(
        find.byKey(const Key('auth-recovery-code')),
        'abcde-fghjk',
      );
      await tester.enterText(
        find.byKey(const Key('auth-password')),
        _newPassword,
      );
      await tester.enterText(
        find.byKey(const Key('auth-confirm-password')),
        _newPassword,
      );
      await tester.ensureVisible(find.byKey(const Key('auth-submit')));
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text('В коде должно быть 20 латинских букв и цифр'),
        findsOneWidget,
      );
      expect(credentials.resets, isEmpty);

      await tester.enterText(
        find.byKey(const Key('auth-recovery-code')),
        'abcde-fghjk-mnpqr-stvwx',
      );
      await tester.ensureVisible(find.byKey(const Key('auth-submit')));
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();

      expect(credentials.resets, [
        ('owner@example.test', 'abcde-fghjk-mnpqr-stvwx', _newPassword),
      ]);
      expect(auth.logins, [('owner@example.test', _newPassword)]);
      // The next code is what the person sees, above the app they are now in.
      expect(find.text(_nextCode), findsOneWidget);
      expect(find.byKey(const Key('signed-in')), findsNothing);
    });

    testWidgets('a refused reset says so without saying which part was wrong', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        const _Host(),
        credentials: _FakeCredentials()
          ..reset = const CredentialFailure(
            CredentialFailureKind.recoveryRejected,
          ),
      );
      container
          .read(authControllerProvider.notifier)
          .showMode(AuthMode.recover);
      await tester.pumpAndSettle();
      await _fillRecovery(tester);

      expect(find.textContaining('Почта или код не подошли'), findsOneWidget);
      // What was typed is still there to be corrected.
      expect(find.text('owner@example.test'), findsOneWidget);
      expect(find.byKey(const Key('recovery-code-page')), findsNothing);
    });

    testWidgets('a new account is shown its code before the app', (
      tester,
    ) async {
      final container = await _pump(tester, const _Host());
      container
          .read(authControllerProvider.notifier)
          .showMode(AuthMode.register);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('auth-display-name')),
        'Синтетический',
      );
      await tester.enterText(
        find.byKey(const Key('auth-email')),
        'owner@example.test',
      );
      await tester.enterText(find.byKey(const Key('auth-password')), _password);
      await tester.enterText(
        find.byKey(const Key('auth-confirm-password')),
        _password,
      );
      await tester.ensureVisible(find.byKey(const Key('auth-submit')));
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();

      expect(find.text(_code), findsOneWidget);
      expect(find.byKey(const Key('signed-in')), findsNothing);
    });

    testWidgets('the code stays until the person says it is kept', (
      tester,
    ) async {
      final container = await _pump(tester, const _CoveredCounter());
      await tester.tap(find.byKey(const Key('counter')));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      container
          .read(pendingRecoveryCodeProvider.notifier)
          .show(RecoveryCode(value: _code, createdAtUtc: _now));
      await tester.pumpAndSettle();

      expect(find.text(_code), findsOneWidget);
      // What is underneath is out of reach: not drawn, and not tappable.
      expect(find.text('1'), findsNothing);
      final done = find.byKey(const Key('recovery-code-done'));
      await tester.ensureVisible(done);
      expect(tester.widget<FilledButton>(done).onPressed, isNull);

      // Going back does not get past it either. Here the code is on the first
      // page there is, so "past it" would be closing the app with the code
      // still unsaved and nowhere but in memory.
      final closed = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') closed.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(closed, isEmpty);
      expect(find.text(_code), findsOneWidget);

      await tester.tap(find.byKey(const Key('recovery-code-kept')));
      await tester.pump();
      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();

      expect(find.text(_code), findsNothing);
      expect(container.read(pendingRecoveryCodeProvider), isNull);
      // And it kept its state while it was covered.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('the code can be copied whole', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(
        tester,
        RecoveryCodePage(
          code: RecoveryCode(value: _code, createdAtUtc: _now),
          onKept: () {},
        ),
      );

      await tester.tap(find.byKey(const Key('recovery-code-copy')));
      await tester.pumpAndSettle();

      expect(copied, [_code]);
      expect(find.text('Код скопирован'), findsOneWidget);
    });

    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets(
        'the code page fits a small phone at 200 percent in $locale',
        (tester) async {
          await _pump(
            tester,
            RecoveryCodePage(
              code: RecoveryCode(value: _code, createdAtUtc: _now),
              onKept: () {},
            ),
            size: const Size(360, 640),
            textScale: 2,
            locale: locale,
          );

          expect(tester.takeException(), isNull);
          // On one line, however large the text: a code broken in two is
          // copied down wrongly.
          // As drawn, not as laid out: the box scales the text down to fit.
          final drawn = tester.getRect(
            find.byKey(const Key('recovery-code-value')),
          );
          expect(drawn.left, greaterThanOrEqualTo(0));
          expect(drawn.right, lessThanOrEqualTo(360));
          expect(
            tester
                .widget<SelectableText>(
                  find.byKey(const Key('recovery-code-value')),
                )
                .maxLines,
            1,
          );
        },
      );

      for (final (label, page) in <(String, Widget)>[
        ('asking for a new code', const RecoveryCodeIssuePage()),
        ('changing the password', const PasswordChangePage()),
        (
          'the Profile rows',
          const Scaffold(
            body: SingleChildScrollView(child: CredentialsSection()),
          ),
        ),
      ]) {
        testWidgets('$label fits a small phone at 200 percent in $locale', (
          tester,
        ) async {
          await _pump(
            tester,
            page,
            credentials: _FakeCredentials()
              ..status = CredentialSuccess(
                RecoveryCodeStatus(exists: true, createdAtUtc: _now),
              ),
            size: const Size(360, 640),
            textScale: 2,
            locale: locale,
          );

          expect(tester.takeException(), isNull);
        });
      }

      testWidgets(
        'the recovery form fits a small phone at 200 percent in $locale',
        (tester) async {
          await _pump(
            tester,
            const AuthPage(mode: AuthMode.recover),
            size: const Size(360, 640),
            textScale: 2,
            locale: locale,
          );

          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('a new code from Profile needs the password', (tester) async {
      final credentials = _FakeCredentials()
        ..issue = const CredentialFailure(
          CredentialFailureKind.passwordRejected,
        );
      final container = await _pump(
        tester,
        const _Pusher(RecoveryCodeIssuePage()),
        credentials: credentials,
      );
      await tester.tap(find.byKey(const Key('push')));
      await tester.pumpAndSettle();

      final submit = find.byKey(const Key('recovery-code-issue-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('recovery-code-issue-password')),
        'not-the-password',
      );
      await tester.pump();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.text('Неверный пароль'), findsOneWidget);
      expect(container.read(pendingRecoveryCodeProvider), isNull);
      expect(find.byKey(const Key('recovery-code-issue-page')), findsOneWidget);

      credentials.issue = CredentialSuccess(
        RecoveryCode(value: _code, createdAtUtc: _now),
      );
      await tester.enterText(
        find.byKey(const Key('recovery-code-issue-password')),
        _password,
      );
      await tester.pump();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(credentials.issued, ['not-the-password', _password]);
      expect(container.read(pendingRecoveryCodeProvider)?.value, _code);
      // The asking page is gone, so the code is not hidden behind it.
      expect(find.byKey(const Key('recovery-code-issue-page')), findsNothing);
    });

    testWidgets('a lost connection issues nothing and says so', (tester) async {
      final container = await _pump(
        tester,
        const RecoveryCodeIssuePage(),
        credentials: _FakeCredentials()
          ..issue = const CredentialFailure(CredentialFailureKind.offline),
      );
      await tester.enterText(
        find.byKey(const Key('recovery-code-issue-password')),
        _password,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('recovery-code-issue-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Не удалось связаться'), findsOneWidget);
      expect(container.read(pendingRecoveryCodeProvider), isNull);
    });

    testWidgets('the password is changed and the page closes', (tester) async {
      final credentials = _FakeCredentials();
      await _pump(
        tester,
        const _Pusher(PasswordChangePage()),
        credentials: credentials,
      );
      await tester.tap(find.byKey(const Key('push')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('password-change-current')),
        _password,
      );
      await tester.enterText(
        find.byKey(const Key('password-change-new')),
        _newPassword,
      );
      await tester.enterText(
        find.byKey(const Key('password-change-confirm')),
        'something-else-123',
      );
      await tester.tap(find.byKey(const Key('password-change-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Пароли не совпадают'), findsOneWidget);
      expect(credentials.changes, isEmpty);

      await tester.enterText(
        find.byKey(const Key('password-change-confirm')),
        _newPassword,
      );
      await tester.tap(find.byKey(const Key('password-change-submit')));
      await tester.pumpAndSettle();

      expect(credentials.changes, [(_password, _newPassword)]);
      expect(find.byKey(const Key('password-change-page')), findsNothing);
      expect(find.textContaining('Пароль изменён'), findsOneWidget);
    });

    testWidgets('a short new password is not sent', (tester) async {
      final credentials = _FakeCredentials();
      await _pump(tester, const PasswordChangePage(), credentials: credentials);
      await tester.enterText(
        find.byKey(const Key('password-change-current')),
        _password,
      );
      await tester.enterText(
        find.byKey(const Key('password-change-new')),
        'short',
      );
      await tester.enterText(
        find.byKey(const Key('password-change-confirm')),
        'short',
      );
      await tester.tap(find.byKey(const Key('password-change-submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('Пароль должен содержать от 12 до 128 символов'),
        findsOneWidget,
      );
      expect(credentials.changes, isEmpty);
    });

    testWidgets('a wrong current password changes nothing and stays', (
      tester,
    ) async {
      await _pump(
        tester,
        const PasswordChangePage(),
        credentials: _FakeCredentials()
          ..change = const CredentialFailure(
            CredentialFailureKind.passwordRejected,
          ),
      );
      await tester.enterText(
        find.byKey(const Key('password-change-current')),
        'not-the-password',
      );
      await tester.enterText(
        find.byKey(const Key('password-change-new')),
        _newPassword,
      );
      await tester.enterText(
        find.byKey(const Key('password-change-confirm')),
        _newPassword,
      );
      await tester.tap(find.byKey(const Key('password-change-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Неверный пароль'), findsOneWidget);
      expect(find.byKey(const Key('password-change-page')), findsOneWidget);
      expect(find.textContaining('Пароль изменён'), findsNothing);
    });

    testWidgets('Profile says when the code was made', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: CredentialsSection()),
        credentials: _FakeCredentials()
          ..status = CredentialSuccess(
            RecoveryCodeStatus(exists: true, createdAtUtc: _now),
          ),
      );

      expect(find.textContaining('16 ноября 2026'), findsOneWidget);
      expect(find.text('Не создан'), findsNothing);
    });

    testWidgets('Profile says when there is no code', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: CredentialsSection()),
        credentials: _FakeCredentials()
          ..status = const CredentialSuccess(RecoveryCodeStatus(exists: false)),
      );

      expect(find.text('Не создан'), findsOneWidget);
    });

    testWidgets('Profile claims nothing when it could not find out', (
      tester,
    ) async {
      await _pump(
        tester,
        const Scaffold(body: CredentialsSection()),
        credentials: _FakeCredentials()
          ..status = const CredentialFailure(CredentialFailureKind.offline),
      );

      expect(find.text('Не создан'), findsNothing);
      expect(find.textContaining('Создан'), findsNothing);
      // Both actions are still there to be used.
      expect(find.byKey(const Key('profile-recovery-code')), findsOneWidget);
      expect(find.byKey(const Key('profile-change-password')), findsOneWidget);
    });
  });

  group('a request that cannot be made at all', () {
    // Two ways to get here. A build with no API_BASE_URL has no credentials
    // repository, so reading the provider throws, and Profile still offers both
    // actions there. And a repository can throw on its own.
    for (final (name, credentials) in <(String, CredentialsRepositoryClient?)>[
      ('in a build with no backend', null),
      ('when the repository throws', _ThrowingCredentials()),
    ]) {
      test('asking for a code $name is refused, not thrown', () async {
        final container = ProviderContainer(
          overrides: _overrides(credentials, null),
        );
        addTearDown(container.dispose);
        final kept = container.listen(
          recoveryCodeIssueControllerProvider,
          (previous, next) {},
        );
        addTearDown(kept.close);

        final code = await container
            .read(recoveryCodeIssueControllerProvider.notifier)
            .submit(_password);

        expect(code, isNull);
        expect(
          container.read(recoveryCodeIssueControllerProvider),
          isA<CredentialFormReady>().having(
            (state) => state.issue,
            'issue',
            CredentialIssue.unavailable,
          ),
        );
      });

      test('changing the password $name is refused, not thrown', () async {
        final container = ProviderContainer(
          overrides: _overrides(credentials, null),
        );
        addTearDown(container.dispose);
        final kept = container.listen(
          passwordChangeControllerProvider,
          (previous, next) {},
        );
        addTearDown(kept.close);

        final changed = await container
            .read(passwordChangeControllerProvider.notifier)
            .submit(currentPassword: _password, newPassword: _newPassword);

        expect(changed, isFalse);
        expect(
          container.read(passwordChangeControllerProvider),
          isA<CredentialFormReady>().having(
            (state) => state.issue,
            'issue',
            CredentialIssue.unavailable,
          ),
        );
      });

      testWidgets('the page asking for a code $name says so and lets go', (
        tester,
      ) async {
        await _pump(
          tester,
          const _Pusher(RecoveryCodeIssuePage()),
          credentials: credentials,
          backend: credentials != null,
        );
        await tester.tap(find.byKey(const Key('push')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('recovery-code-issue-password')),
          _password,
        );
        await tester.pump();
        final submit = find.byKey(const Key('recovery-code-issue-submit'));
        await tester.tap(submit);
        // Not pumpAndSettle: a page left waiting never settles, and the
        // assertions below should be what says so.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.textContaining('Сервер не смог выполнить запрос'),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

        // Back is not held shut by a request that was never sent.
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const Key('recovery-code-issue-page')), findsNothing);
      });

      testWidgets('the password page $name says so and lets go', (
        tester,
      ) async {
        await _pump(
          tester,
          const _Pusher(PasswordChangePage()),
          credentials: credentials,
          backend: credentials != null,
        );
        await tester.tap(find.byKey(const Key('push')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('password-change-current')),
          _password,
        );
        await tester.enterText(
          find.byKey(const Key('password-change-new')),
          _newPassword,
        );
        await tester.enterText(
          find.byKey(const Key('password-change-confirm')),
          _newPassword,
        );
        final submit = find.byKey(const Key('password-change-submit'));
        await tester.tap(submit);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.textContaining('Сервер не смог выполнить запрос'),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        expect(find.textContaining('Пароль изменён'), findsNothing);

        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const Key('password-change-page')), findsNothing);
      });
    }
  });

  group('what a field says before anything is sent', () {
    testWidgets('an empty current password is asked for, not called wrong', (
      tester,
    ) async {
      final credentials = _FakeCredentials();
      await _pump(tester, const PasswordChangePage(), credentials: credentials);
      await tester.enterText(
        find.byKey(const Key('password-change-new')),
        _newPassword,
      );
      await tester.enterText(
        find.byKey(const Key('password-change-confirm')),
        _newPassword,
      );
      await tester.tap(find.byKey(const Key('password-change-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Введите текущий пароль'), findsOneWidget);
      // Nothing was checked, so nothing can have been wrong.
      expect(find.text('Неверный пароль'), findsNothing);
      expect(credentials.changes, isEmpty);
    });

    test('a code of the wrong shape is told what it must be', () {
      const instruction = {
        'ru': 'должно быть 20',
        'uk': 'має бути 20',
        'en': 'must have 20',
        'de': 'muss 20',
      };
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        expect(
          l10n.recoveryCodeInvalid,
          contains(instruction[locale.languageCode]),
          reason: locale.languageCode,
        );
      }
    });

    test('asking for a password is never worded as refusing one', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        expect(l10n.currentPasswordRequired, isNotEmpty);
        expect(
          l10n.currentPasswordRequired,
          isNot(l10n.credentialPasswordRejected),
          reason: locale.languageCode,
        );
      }
    });
  });
}

const _code = 'ABCDE-FGHJK-MNPQR-STVWX';
const _nextCode = '01234-56789-ABCDE-FGHJK';
const _password = 'synthetic-password-123';
const _newPassword = 'synthetic-password-456';
const _at = '2026-11-16T09:30:00Z';
const _userId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
final _now = DateTime.utc(2026, 11, 16, 9, 30);

Map<String, Object?> _codeJson(String code) => {
  'schemaVersion': '1',
  'recoveryCode': code,
  'createdAt': _at,
};

Map<String, Object?>? _errorJson(String? code) => code == null
    ? null
    : {
        'detail': {'code': code},
      };

CredentialFailureKind _kind<T>(CredentialResult<T> result) =>
    (result as CredentialFailure<T>).kind;

CredentialsApi _api(_Recording adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  addTearDown(() => dio.close(force: true));
  return CredentialsApi(dio: dio, baseUri: Uri.parse('https://example.test/'));
}

AuthTokenBundle _bundle({String accessToken = 'synthetic-access-token'}) =>
    AuthTokenBundle(
      accessToken: accessToken,
      refreshToken: 'synthetic-refresh-token',
      accessExpiresAtUtc: _now.add(const Duration(minutes: 10)),
      refreshExpiresAtUtc: _now.add(const Duration(days: 30)),
      cacheScopeId: _userId,
      user: const AuthUser(id: _userId, displayName: 'Синтетический'),
    );

AuthSession _session(String accessToken, {required int minutes}) => AuthSession(
  accessToken: accessToken,
  refreshToken: 'synthetic-refresh-token',
  accessExpiresAtUtc: _now.add(Duration(minutes: minutes)),
  refreshExpiresAtUtc: _now.add(const Duration(days: 30)),
  cacheScopeId: _userId,
  revision: '0123456789abcdef0123456789abcdef',
);

ProviderContainer _container({
  required _FakeCredentials credentials,
  _FakeAuthApi? auth,
}) {
  return ProviderContainer(overrides: _overrides(credentials, auth));
}

/// [credentials] left out is a build with no backend: the provider is the
/// real one, and without an API_BASE_URL it throws.
List<Override> _overrides(
  CredentialsRepositoryClient? credentials,
  _FakeAuthApi? auth,
) {
  return [
    initialAppSettingsProvider.overrideWithValue(const AppSettings()),
    authRepositoryProvider.overrideWithValue(
      AuthRepository(api: auth ?? _FakeAuthApi(), sessionStore: _FakeStore()),
    ),
    if (credentials != null)
      credentialsRepositoryProvider.overrideWithValue(credentials),
    waitingPhraseStoreProvider.overrideWithValue(const NoWaitingPhraseStore()),
  ];
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget home, {
  CredentialsRepositoryClient? credentials,
  _FakeAuthApi? auth,
  bool backend = true,
  Size size = const Size(360, 800),
  double textScale = 1,
  Locale locale = const Locale('ru'),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: _overrides(
      backend ? credentials ?? _FakeCredentials() : null,
      auth,
    ),
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(AppAccent.teal),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _fillRecovery(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('auth-email')),
    'owner@example.test',
  );
  await tester.enterText(find.byKey(const Key('auth-recovery-code')), _code);
  await tester.enterText(find.byKey(const Key('auth-password')), _newPassword);
  await tester.enterText(
    find.byKey(const Key('auth-confirm-password')),
    _newPassword,
  );
  await tester.ensureVisible(find.byKey(const Key('auth-submit')));
  await tester.tap(find.byKey(const Key('auth-submit')));
  await tester.pumpAndSettle();
}

/// What the auth gate does with the controller's state, without the build
/// switch that keeps the gate itself out of a test.
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    return RecoveryCodeCover(
      child: switch (state) {
        AuthSignedOut(:final mode, :final notice, :final issue) => AuthPage(
          mode: mode,
          notice: notice,
          issue: issue,
        ),
        AuthSubmitting(:final mode) => AuthPage(mode: mode, isSubmitting: true),
        AuthSignedIn() => const Scaffold(
          body: Text('signed in', key: Key('signed-in')),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _CoveredCounter extends StatelessWidget {
  const _CoveredCounter();

  @override
  Widget build(BuildContext context) {
    return const RecoveryCodeCover(child: Scaffold(body: _Counter()));
  }
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: const Key('counter'),
      onPressed: () => setState(() => _count += 1),
      child: Text('$_count'),
    );
  }
}

/// Opens a page the way Profile does, under a cover, so leaving it can be seen.
class _Pusher extends StatelessWidget {
  const _Pusher(this.page);

  final Widget page;

  @override
  Widget build(BuildContext context) {
    return RecoveryCodeCover(
      child: Scaffold(
        body: TextButton(
          key: const Key('push'),
          onPressed: () => Navigator.of(
            context,
          ).push<void>(MaterialPageRoute<void>(builder: (_) => page)),
          child: const Text('open'),
        ),
      ),
    );
  }
}

final class _FakeCredentials implements CredentialsRepositoryClient {
  CredentialResult<RecoveryCode> issue = CredentialSuccess(
    RecoveryCode(value: _code, createdAtUtc: _now),
  );
  CredentialResult<RecoveryCode> reset = CredentialSuccess(
    RecoveryCode(value: _nextCode, createdAtUtc: _now),
  );
  CredentialResult<void> change = const CredentialSuccess<void>(null);
  CredentialResult<RecoveryCodeStatus> status = const CredentialSuccess(
    RecoveryCodeStatus(exists: false),
  );

  final issued = <String>[];
  final resets = <(String, String, String)>[];
  final changes = <(String, String)>[];

  @override
  Future<CredentialResult<RecoveryCodeStatus>> readRecoveryCodeStatus() async =>
      status;

  @override
  Future<CredentialResult<RecoveryCode>> issueRecoveryCode({
    required String password,
  }) async {
    issued.add(password);
    return issue;
  }

  @override
  Future<CredentialResult<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changes.add((currentPassword, newPassword));
    return change;
  }

  @override
  Future<CredentialResult<RecoveryCode>> resetPassword({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {
    resets.add((email, recoveryCode, newPassword));
    return reset;
  }
}

/// A repository that fails instead of answering.
final class _ThrowingCredentials implements CredentialsRepositoryClient {
  @override
  Future<CredentialResult<RecoveryCodeStatus>> readRecoveryCodeStatus() =>
      throw StateError('synthetic');

  @override
  Future<CredentialResult<RecoveryCode>> issueRecoveryCode({
    required String password,
  }) => throw StateError('synthetic');

  @override
  Future<CredentialResult<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw StateError('synthetic');

  @override
  Future<CredentialResult<RecoveryCode>> resetPassword({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) => throw StateError('synthetic');
}

final class _FakeCredentialsApi implements CredentialsApiClient {
  final tokens = <String>[];

  @override
  Future<CredentialResult<RecoveryCodeStatus>> readRecoveryCodeStatus({
    required String accessToken,
  }) async {
    tokens.add(accessToken);
    return const CredentialSuccess(RecoveryCodeStatus(exists: false));
  }

  @override
  Future<CredentialResult<RecoveryCode>> issueRecoveryCode({
    required String accessToken,
    required String password,
  }) async {
    tokens.add(accessToken);
    return CredentialSuccess(RecoveryCode(value: _code, createdAtUtc: _now));
  }

  @override
  Future<CredentialResult<void>> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) async {
    tokens.add(accessToken);
    return const CredentialSuccess<void>(null);
  }

  @override
  Future<CredentialResult<RecoveryCode>> resetPassword({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {
    return CredentialSuccess(
      RecoveryCode(value: _nextCode, createdAtUtc: _now),
    );
  }
}

final class _FakeAuthApi implements AuthApiClient {
  AuthFailureKind? registerFailure;
  AuthFailureKind? loginFailure;

  /// What a refresh answers with; none means the session cannot be renewed.
  AuthTokenBundle? refreshed;
  final logins = <(String, String)>[];

  @override
  Future<AuthSessionApiResult> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final failure = registerFailure;
    return failure == null
        ? AuthSessionApiData(_bundle())
        : AuthSessionApiFailure(failure);
  }

  @override
  Future<AuthSessionApiResult> login({
    required String email,
    required String password,
  }) async {
    logins.add((email, password));
    final failure = loginFailure;
    return failure == null
        ? AuthSessionApiData(_bundle())
        : AuthSessionApiFailure(failure);
  }

  @override
  Future<AuthSessionApiResult> refresh({required String refreshToken}) async {
    final tokens = refreshed;
    return tokens == null
        ? const AuthSessionApiFailure(AuthFailureKind.invalidRefresh)
        : AuthSessionApiData(tokens);
  }

  @override
  Future<void> logout({required String refreshToken}) async {}
}

final class _FakeStore implements AuthSessionStore {
  AuthSession? session;

  @override
  Future<AuthSession?> readAuthSession() async => session;

  @override
  Future<AuthSession> saveAuthenticatedSession(AuthTokenBundle tokens) async {
    return session = _stored(tokens);
  }

  @override
  Future<AuthSession> rotateAuthenticatedSession({
    required AuthTokenBundle tokens,
    required AuthSession expectedSession,
  }) async {
    return session = _stored(tokens);
  }

  @override
  Future<bool> clearSessionIfCurrent(AuthSession expectedSession) async {
    session = null;
    return true;
  }

  @override
  Future<void> clearSession() async => session = null;

  static AuthSession _stored(AuthTokenBundle tokens) => AuthSession(
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken,
    accessExpiresAtUtc: tokens.accessExpiresAtUtc,
    refreshExpiresAtUtc: tokens.refreshExpiresAtUtc,
    cacheScopeId: tokens.cacheScopeId,
    revision: '0123456789abcdef0123456789abcdef',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Answers every request the same way and remembers what was asked.
final class _Recording implements HttpClientAdapter {
  _Recording(this._status, this._json);

  final int _status;
  final Map<String, Object?>? _json;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = _json == null ? '' : jsonEncode(_json);
    return ResponseBody.fromString(
      body,
      _status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        Headers.contentLengthHeader: [utf8.encode(body).length.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
