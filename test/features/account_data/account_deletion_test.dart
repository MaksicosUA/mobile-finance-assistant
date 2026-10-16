import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/account_data/application/account_deletion_controller.dart';
import 'package:mobile_finance_assistant/features/account_data/presentation/account_data_section.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

/// Asking for one's own account to be erased a week from now (ADR 0030).
void main() {
  final dueAt = DateTime.utc(2026, 10, 23, 12);

  test(
    'an accepted request hands the date back and changes nothing itself',
    () async {
      final repository = _FakeRepository.scheduling(dueAt);
      final completed = <DateTime>[];
      final container = _container(repository, completed);
      addTearDown(container.dispose);
      final keepAlive = container.listen(
        accountDeletionControllerProvider,
        (_, _) {},
      );
      addTearDown(keepAlive.close);

      final answer = await container
          .read(accountDeletionControllerProvider.notifier)
          .submit('synthetic-password');

      expect(answer, dueAt);
      expect(repository.passwords, ['synthetic-password']);
      // The screen leaves first, then the session goes; the controller does
      // neither, so a page left on top of the sign-in screen cannot happen.
      expect(completed, isEmpty);
      expect(
        container.read(accountDeletionControllerProvider),
        isA<AccountDeletionSubmitting>(),
      );
    },
  );

  for (final (label, failure, code, issue) in [
    (
      'a wrong password',
      FinanceEntryFailureKind.rejected,
      FinanceEntryErrorCode.passwordRejected,
      AccountDeletionIssue.passwordRejected,
    ),
    (
      'no connection',
      FinanceEntryFailureKind.offline,
      null,
      AccountDeletionIssue.unreachable,
    ),
    (
      'an ended session',
      FinanceEntryFailureKind.unauthorized,
      null,
      AccountDeletionIssue.authenticationRequired,
    ),
    (
      'a server that cannot take it',
      FinanceEntryFailureKind.serviceUnavailable,
      FinanceEntryErrorCode.accountDataUnavailable,
      AccountDeletionIssue.unavailable,
    ),
  ]) {
    test('$label schedules nothing and says why', () async {
      final completed = <DateTime>[];
      final container = _container(
        _FakeRepository.failing(failure, code),
        completed,
      );
      addTearDown(container.dispose);
      final keepAlive = container.listen(
        accountDeletionControllerProvider,
        (_, _) {},
      );
      addTearDown(keepAlive.close);

      final answer = await container
          .read(accountDeletionControllerProvider.notifier)
          .submit('synthetic-password');

      expect(answer, isNull);
      expect(completed, isEmpty);
      final state = container.read(accountDeletionControllerProvider);
      expect((state as AccountDeletionReady).issue, issue);
    });
  }

  testWidgets('Profile leads to the screen, which says what will happen', (
    tester,
  ) async {
    await _pumpProfileSection(tester, _FakeRepository.scheduling(dueAt), []);

    await tester.tap(find.byKey(const Key('profile-delete-account')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-deletion-page')), findsOneWidget);
    expect(find.text('Аккаунт удалится через 7 дней'), findsOneWidget);
    expect(find.textContaining('войдите в течение 7 дней'), findsOneWidget);
    expect(find.textContaining('до 14 дней'), findsOneWidget);
    expect(
      find.byKey(const Key('account-deletion-export-first')),
      findsOneWidget,
    );
    // Nothing to send without a password.
    expect(_submitButton(tester).onPressed, isNull);
  });

  testWidgets('confirming leaves every pushed screen, then signs out', (
    tester,
  ) async {
    final repository = _FakeRepository.scheduling(dueAt);
    final completed = <DateTime>[];
    await _pumpProfileSection(tester, repository, completed);
    await tester.tap(find.byKey(const Key('profile-delete-account')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('account-deletion-password')),
      'synthetic-password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('account-deletion-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-deletion-confirm')), findsOneWidget);
    expect(repository.passwords, isEmpty, reason: 'not before confirming');

    await tester.tap(find.byKey(const Key('account-deletion-confirm-accept')));
    await tester.pumpAndSettle();

    expect(repository.passwords, ['synthetic-password']);
    expect(completed, [dueAt]);
    expect(find.byKey(const Key('account-deletion-page')), findsNothing);
    expect(find.byKey(const Key('profile-delete-account')), findsOneWidget);
  });

  testWidgets('cancelling the confirmation asks the server nothing', (
    tester,
  ) async {
    final repository = _FakeRepository.scheduling(dueAt);
    final completed = <DateTime>[];
    await _pumpProfileSection(tester, repository, completed);
    await tester.tap(find.byKey(const Key('profile-delete-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-deletion-password')),
      'synthetic-password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('account-deletion-submit')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(repository.passwords, isEmpty);
    expect(completed, isEmpty);
    expect(find.byKey(const Key('account-deletion-page')), findsOneWidget);
  });

  testWidgets('a wrong password is said beside the field, and nothing ends', (
    tester,
  ) async {
    final completed = <DateTime>[];
    await _pumpProfileSection(
      tester,
      _FakeRepository.failing(
        FinanceEntryFailureKind.rejected,
        FinanceEntryErrorCode.passwordRejected,
      ),
      completed,
    );
    await tester.tap(find.byKey(const Key('profile-delete-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-deletion-password')),
      'wrong',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('account-deletion-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-deletion-confirm-accept')));
    await tester.pumpAndSettle();

    expect(find.text('Неверный пароль'), findsOneWidget);
    expect(completed, isEmpty);
    expect(find.byKey(const Key('account-deletion-page')), findsOneWidget);
  });

  testWidgets('unsent operations are named, and do not lock erasure away', (
    tester,
  ) async {
    // A delivery lock is never lifted automatically (ADR 0014); if it could
    // block erasure, some people could never leave.
    await _pumpProfileSection(
      tester,
      _FakeRepository.scheduling(dueAt),
      [],
      unsent: 2,
    );
    await tester.tap(find.byKey(const Key('profile-delete-account')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-deletion-unsent')), findsOneWidget);
    expect(find.textContaining('до сервера: 2'), findsOneWidget);
    // The warning pushes the field below a 360 x 800 fold; people scroll.
    await tester.scrollUntilVisible(
      find.byKey(const Key('account-deletion-submit')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('account-deletion-page')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('account-deletion-password')),
      'synthetic-password',
    );
    await tester.pump();
    expect(_submitButton(tester).onPressed, isNotNull);
  });
}

FilledButton _submitButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const Key('account-deletion-submit')),
);

ProviderContainer _container(
  _FakeRepository repository,
  List<DateTime> completed,
) {
  return ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      accountDeletionCompletionProvider.overrideWithValue(
        (dueAt) async => completed.add(dueAt),
      ),
    ],
  );
}

Future<void> _pumpProfileSection(
  WidgetTester tester,
  _FakeRepository repository,
  List<DateTime> completed, {
  int unsent = 0,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
        financeEntryRepositoryProvider.overrideWithValue(repository),
        accountDeletionCompletionProvider.overrideWithValue(
          (dueAt) async => completed.add(dueAt),
        ),
        unsentOperationCountProvider.overrideWithValue(unsent),
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
        home: const Scaffold(body: AccountDataSection()),
      ),
    ),
  );
}

final class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository.scheduling(DateTime dueAt)
    : _result = FinanceEntrySuccess<DateTime>(
        requestId: 'req_synthetic',
        value: dueAt,
      );

  _FakeRepository.failing(
    FinanceEntryFailureKind kind,
    FinanceEntryErrorCode? code,
  ) : _result = FinanceEntryFailureResult<DateTime>(
        FinanceEntryFailure(kind: kind, requestId: 'req_synthetic', code: code),
      );

  final FinanceEntryResult<DateTime> _result;
  final List<String> passwords = [];

  @override
  Future<FinanceEntryResult<DateTime>> requestAccountDeletion({
    required String password,
  }) async {
    passwords.add(password);
    return _result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
