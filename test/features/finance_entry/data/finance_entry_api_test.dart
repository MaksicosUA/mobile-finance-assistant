import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_api.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';

void main() {
  group('FinanceEntryApi', () {
    test(
      'confirms a baseline correction that moves the date earlier',
      () async {
        final adapter = _QueueAdapter([
          _JsonResponse(
            200,
            _baselineEvaluation(decision: 'NEEDS_CONFIRMATION'),
          ),
        ]);
        final api = _api(adapter);

        final result = await api.evaluateBaseline(
          accessToken: 'access-token',
          draft: _baselineModel(),
        );

        final review =
            (result as FinanceEntrySuccess<FinanceBaselineEvaluation>).value
                as FinanceBaselineNeedsConfirmation;
        expect(review.currentOpeningBalanceOn, '2026-07-28');
        expect(review.earliestOperationOn, isNull);
        expect(review.draft.openingBalanceOn, '2026-01-01');
        expect(
          adapter.requests.single.uri.path,
          '/api/v1/accounts/baseline/evaluate',
        );
      },
    );

    test('corrects the reporting timezone in one phase', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(200, const {
          'schemaVersion': '1',
          'idempotentReplay': false,
          'accountId': '11111111-1111-4111-8111-111111111111',
          'canonicalTimezone': 'Europe/Kyiv',
          'timezoneRevision': 2,
        }),
      ]);
      final api = _api(adapter);

      final result = await api.correctTimezone(
        accessToken: 'access-token',
        command: _timezoneCommand(),
      );

      final settled =
          (result as FinanceEntrySuccess<FinanceTimezoneCorrected>).value;
      expect(settled.canonicalTimezone, 'Europe/Kyiv');
      expect(settled.timezoneRevision, 2);
      expect(adapter.requests.single.uri.path, '/api/v1/accounts/timezone');
      expect(adapter.requests.single.data, {
        'schemaVersion': '1',
        'commandId': '22222222-2222-4222-8222-222222222222',
        'accountId': '11111111-1111-4111-8111-111111111111',
        'canonicalTimezone': 'Europe/Kyiv',
        'requestedAt': '2026-09-02T10:30:00.000Z',
      });
    });

    test('surfaces the reason a timezone correction was refused', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(422, const {
          'detail': {
            'code': 'TIMEZONE_REJECTED',
            'issues': <Object?>[],
            'timezoneIssues': [
              {
                'code': 'TIMEZONE_BEHIND_RECORDED_OPERATIONS',
                'field': 'canonicalTimezone',
              },
            ],
          },
        }),
      ]);

      final failure = _failure(
        await _api(adapter).correctTimezone(
          accessToken: 'access-token',
          command: _timezoneCommand(),
        ),
      );

      expect(failure.code, FinanceEntryErrorCode.timezoneRejected);
      expect(
        failure.timezoneIssues.single.code,
        FinanceTimezoneIssueCode.timezoneBehindRecordedOperations,
      );
      expect(failure.kind, FinanceEntryFailureKind.rejected);
    });

    test('a refusal from another contract is not accepted here', () async {
      // Each route answers in its own code space. Reading a baseline refusal
      // on this one would mean a response was routed somewhere it does not
      // belong, which is a malformed answer, not a rejection to act on.
      final adapter = _QueueAdapter([
        _JsonResponse(422, const {
          'detail': {
            'code': 'BASELINE_REJECTED',
            'issues': <Object?>[],
            'baselineIssues': [
              {'code': 'BASELINE_NOT_EARLIER', 'field': 'openingBalanceOn'},
            ],
          },
        }),
      ]);

      final failure = _failure(
        await _api(adapter).correctTimezone(
          accessToken: 'access-token',
          command: _timezoneCommand(),
        ),
      );

      expect(failure.code, isNull);
      expect(failure.timezoneIssues, isEmpty);
    });

    test('a rejection with no reason is not a rejection', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(422, const {
          'detail': {
            'code': 'TIMEZONE_REJECTED',
            'issues': <Object?>[],
            'timezoneIssues': <Object?>[],
          },
        }),
      ]);

      final failure = _failure(
        await _api(adapter).correctTimezone(
          accessToken: 'access-token',
          command: _timezoneCommand(),
        ),
      );

      expect(failure.code, isNull);
    });

    test('surfaces the reason a baseline correction was refused', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(
          200,
          _baselineEvaluation(
            decision: 'REJECT',
            issues: const [
              {'code': 'BASELINE_NOT_EARLIER', 'field': 'openingBalanceOn'},
            ],
          ),
        ),
      ]);
      final api = _api(adapter);

      final result = await api.evaluateBaseline(
        accessToken: 'access-token',
        draft: _baselineModel(),
      );

      final rejected =
          (result as FinanceEntrySuccess<FinanceBaselineEvaluation>).value
              as FinanceBaselineRejected;
      expect(
        rejected.issues.single.code,
        FinanceBaselineIssueCode.baselineNotEarlier,
      );
    });

    test(
      'rejects non-canonical dates in baseline evaluation responses',
      () async {
        final invalidCurrent = _baselineEvaluation(
          decision: 'NEEDS_CONFIRMATION',
        )..['currentOpeningBalanceOn'] = '2026-02-30';
        final invalidEarliest = _baselineEvaluation(
          decision: 'NEEDS_CONFIRMATION',
        )..['earliestOperationOn'] = '2026-7-01';
        final adapter = _QueueAdapter([
          _JsonResponse(200, invalidCurrent),
          _JsonResponse(200, invalidEarliest),
        ]);
        final api = _api(adapter);

        final current = await api.evaluateBaseline(
          accessToken: 'access-token',
          draft: _baselineModel(),
        );
        final earliest = await api.evaluateBaseline(
          accessToken: 'access-token',
          draft: _baselineModel(),
        );

        expect(
          _failure(current).kind,
          FinanceEntryFailureKind.malformedResponse,
        );
        expect(
          _failure(earliest).kind,
          FinanceEntryFailureKind.malformedResponse,
        );
      },
    );

    test(
      'commits a baseline correction and reports the previous date',
      () async {
        final adapter = _QueueAdapter([_JsonResponse(200, _baselineCommit())]);
        final api = _api(adapter);

        final result = await api.commitBaseline(
          accessToken: 'access-token',
          command: _baselineCommand(),
        );

        final commit =
            (result as FinanceEntrySuccess<FinanceBaselineCommit>).value;
        expect(commit.idempotentReplay, isFalse);
        expect(commit.previousOpeningBalanceOn, '2026-07-28');
        expect(commit.account.openingBalanceOn, '2026-01-01');
        expect(
          adapter.requests.single.uri.path,
          '/api/v1/accounts/baseline/commit',
        );
      },
    );

    test('refuses a commit response that contradicts the review', () async {
      // The server must never answer with a different account or a date that
      // is later than the baseline it claims to have replaced.
      final wrongAccount = _baselineCommit();
      (wrongAccount['account']! as Map<String, Object?>)['openingBalanceOn'] =
          '2026-09-01';
      final movedLater = _baselineCommit(previous: '2025-01-01');
      final adapter = _QueueAdapter([
        _JsonResponse(200, wrongAccount),
        _JsonResponse(200, movedLater),
      ]);
      final api = _api(adapter);

      final mismatched = await api.commitBaseline(
        accessToken: 'access-token',
        command: _baselineCommand(),
      );
      final later = await api.commitBaseline(
        accessToken: 'access-token',
        command: _baselineCommand(),
      );

      expect(
        _failure(mismatched).kind,
        FinanceEntryFailureKind.malformedResponse,
      );
      expect(_failure(later).kind, FinanceEntryFailureKind.malformedResponse);
    });

    test(
      'rejects a non-canonical previous date in a baseline commit response',
      () async {
        final adapter = _QueueAdapter([
          _JsonResponse(200, _baselineCommit(previous: '2026-07-1')),
        ]);
        final api = _api(adapter);

        final result = await api.commitBaseline(
          accessToken: 'access-token',
          command: _baselineCommand(),
        );

        expect(
          _failure(result).kind,
          FinanceEntryFailureKind.malformedResponse,
        );
      },
    );

    test(
      'maps baseline HTTP rejection and preserves its structured issues',
      () async {
        final adapter = _QueueAdapter([
          const _JsonResponse(422, {
            'detail': {
              'code': 'BASELINE_REJECTED',
              'issues': <Object?>[],
              'baselineIssues': [
                {
                  'code': 'BASELINE_AFTER_EXISTING_OPERATION',
                  'field': 'openingBalanceOn',
                },
              ],
            },
          }),
        ]);
        final api = _api(adapter);

        final result = await api.commitBaseline(
          accessToken: 'access-token',
          command: _baselineCommand(),
        );

        final failure = _failure(result);
        expect(failure.kind, FinanceEntryFailureKind.rejected);
        expect(failure.code, FinanceEntryErrorCode.baselineRejected);
        expect(failure.issues, isEmpty);
        expect(failure.baselineIssues, hasLength(1));
        expect(
          failure.baselineIssues.single.code,
          FinanceBaselineIssueCode.baselineAfterExistingOperation,
        );
      },
    );

    test(
      'maps strict account unavailable 404 for both baseline endpoints',
      () async {
        const unavailable = {
          'detail': {'code': 'ACCOUNT_UNAVAILABLE', 'issues': <Object?>[]},
        };
        final adapter = _QueueAdapter([
          const _JsonResponse(404, unavailable),
          const _JsonResponse(404, unavailable),
        ]);
        final api = _api(adapter);

        final evaluated = await api.evaluateBaseline(
          accessToken: 'access-token',
          draft: _baselineModel(),
        );
        final committed = await api.commitBaseline(
          accessToken: 'access-token',
          command: _baselineCommand(),
        );

        for (final result in [evaluated, committed]) {
          final failure = switch (result) {
            FinanceEntryFailureResult(:final failure) => failure,
            _ => throw StateError('Expected a baseline failure.'),
          };
          expect(failure.kind, FinanceEntryFailureKind.conflict);
          expect(failure.code, FinanceEntryErrorCode.accountUnavailable);
          expect(failure.issues, isEmpty);
          expect(failure.baselineIssues, isEmpty);
        }
      },
    );

    test(
      'fails closed for malformed or misplaced account unavailable',
      () async {
        const unavailable = {
          'detail': {'code': 'ACCOUNT_UNAVAILABLE', 'issues': <Object?>[]},
        };
        final adapter = _QueueAdapter([
          const _JsonResponse(404, {
            'detail': {'code': 'ACCOUNT_UNAVAILABLE'},
          }),
          const _JsonResponse(422, unavailable),
          const _JsonResponse(404, unavailable),
        ]);
        final api = _api(adapter);

        final malformed = await api.evaluateBaseline(
          accessToken: 'access-token',
          draft: _baselineModel(),
        );
        final wrongStatus = await api.evaluateBaseline(
          accessToken: 'access-token',
          draft: _baselineModel(),
        );
        final wrongEndpoint = await api.evaluateAccount(
          accessToken: 'access-token',
          draft: FinanceAccountDraft.fromJson(_accountDraft()),
        );

        expect(
          _failure(malformed).kind,
          FinanceEntryFailureKind.malformedResponse,
        );
        expect(
          _failure(wrongStatus).kind,
          FinanceEntryFailureKind.malformedResponse,
        );
        expect(
          _failure(wrongEndpoint).kind,
          FinanceEntryFailureKind.malformedResponse,
        );
      },
    );

    test('keeps the legacy account rejection wire shape valid', () async {
      final adapter = _QueueAdapter([
        const _JsonResponse(422, {
          'detail': {
            'code': 'ACCOUNT_REJECTED',
            'issues': [
              {
                'code': 'OPENING_BALANCE_DATE_IN_FUTURE',
                'field': 'openingBalanceOn',
              },
            ],
          },
        }),
      ]);
      final api = _api(adapter);

      final result = await api.evaluateAccount(
        accessToken: 'access-token',
        draft: FinanceAccountDraft.fromJson(_accountDraft()),
      );

      final failure = _failure(result);
      expect(failure.kind, FinanceEntryFailureKind.rejected);
      expect(failure.code, FinanceEntryErrorCode.accountRejected);
      expect(
        failure.issues.single.code,
        FinanceIssueCode.openingBalanceDateInFuture,
      );
      expect(failure.baselineIssues, isEmpty);
    });

    test('lists the strict authoritative account setup', () async {
      final adapter = _QueueAdapter([_JsonResponse(200, _accountSetup())]);
      final api = _api(adapter);

      final result = await api.listAccounts(accessToken: 'access-token');

      final success = result as FinanceEntrySuccess<FinanceAccountSetup>;
      expect(success.value.isInitialized, isTrue);
      expect(success.value.account?.openingBalance, '1000');
      expect(success.value.canonicalTimezone, 'Europe/Berlin');
      expect(adapter.requests.single.uri.path, '/api/v1/accounts');
      expect(adapter.requests.single.method, 'GET');
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer access-token',
      );
      expect(
        adapter.requests.single.headers['X-Correlation-ID'],
        'req_finance_test',
      );
    });

    test(
      'commits the exact canonical account draft returned by evaluate',
      () async {
        final canonicalDraft = _accountDraft(openingBalance: '1000');
        final adapter = _QueueAdapter([
          _JsonResponse(
            200,
            _evaluation(draft: canonicalDraft, decision: 'NEEDS_CONFIRMATION'),
          ),
          _JsonResponse(
            201,
            _accountCommit(
              draft: canonicalDraft,
              confirmedAt: '2026-07-28T12:01:00Z',
            ),
          ),
        ]);
        final api = _api(adapter);
        final localDraft = FinanceAccountDraft(
          commandId: _accountCommandId,
          name: 'Main account',
          currency: 'EUR',
          openingBalance: '1000.00',
          openingBalanceOn: '2026-07-28',
          canonicalTimezone: 'Europe/Berlin',
        );

        final evaluated = await api.evaluateAccount(
          accessToken: 'access-token',
          draft: localDraft,
        );
        final review =
            (evaluated as FinanceEntrySuccess<FinanceAccountEvaluation>).value
                as FinanceAccountNeedsConfirmation;
        expect(review.draft.openingBalance, '1000');
        final command = FinanceAccountCommitCommand.fromReview(
          review: review,
          confirmedAt: DateTime.utc(2026, 7, 28, 12, 1),
        );
        final committed = await api.commitAccount(
          accessToken: 'access-token',
          command: command,
        );

        expect(committed, isA<FinanceEntrySuccess<FinanceAccountCommit>>());
        final body = adapter.requests[1].data as Map<String, Object?>;
        final sentDraft = body['draft'] as Map<String, Object?>;
        expect(sentDraft, canonicalDraft);
        expect(sentDraft['openingBalance'], isA<String>());
        expect(sentDraft['openingBalance'], isNot(isA<double>()));
        expect(body['draftHash'], _draftHash);
      },
    );

    test(
      'maps operation REJECT issues without treating it as transport failure',
      () async {
        final adapter = _QueueAdapter([
          _JsonResponse(
            200,
            _evaluation(
              draft: _operationDraft(accountId: null),
              decision: 'REJECT',
              issues: const [
                {'code': 'ACCOUNT_REQUIRED', 'field': 'accountId'},
              ],
            ),
          ),
        ]);
        final api = _api(adapter);

        final result = await api.evaluateOperation(
          accessToken: 'access-token',
          draft: _operationModel(accountId: null),
        );

        final rejection =
            (result as FinanceEntrySuccess<FinanceOperationEvaluation>).value
                as FinanceOperationRejected;
        expect(rejection.issues.single.code, FinanceIssueCode.accountRequired);
        expect(rejection.issues.single.field, FinanceIssueField.accountId);
      },
    );

    test(
      'operation commit preserves decimal strings and reviewed draft',
      () async {
        final canonicalDraft = _operationDraft(
          accountId: _accountId,
          amount: '35',
        );
        final adapter = _QueueAdapter([
          _JsonResponse(
            200,
            _evaluation(draft: canonicalDraft, decision: 'NEEDS_CONFIRMATION'),
          ),
          _JsonResponse(
            201,
            _operationCommit(
              draft: canonicalDraft,
              confirmedAt: '2026-07-28T12:01:00Z',
            ),
          ),
        ]);
        final api = _api(adapter);
        final evaluation = await api.evaluateOperation(
          accessToken: 'access-token',
          draft: _operationModel(accountId: _accountId, amount: '35.00'),
        );
        final review =
            (evaluation as FinanceEntrySuccess<FinanceOperationEvaluation>)
                    .value
                as FinanceOperationNeedsConfirmation;
        final command = FinanceOperationCommitCommand.fromReview(
          review: review,
          confirmedAt: DateTime.utc(2026, 7, 28, 12, 1),
        );

        final result = await api.commitOperation(
          accessToken: 'access-token',
          command: command,
        );

        final receipt =
            (result as FinanceEntrySuccess<FinanceOperationCommit>).value;
        expect(receipt.operation.amount, '35');
        final body = adapter.requests[1].data as Map<String, Object?>;
        expect((body['draft'] as Map<String, Object?>)['amount'], '35');
        expect(
          (body['draft'] as Map<String, Object?>)['amount'],
          isA<String>(),
        );
      },
    );

    test('maps safe HTTP errors by status and bounded reason code', () async {
      final adapter = _QueueAdapter([
        const _JsonResponse(401, {'detail': 'Authentication required'}),
        const _JsonResponse(409, {
          'detail': {'code': 'COMMAND_CONFLICT', 'issues': <Object?>[]},
        }),
        const _JsonResponse(422, {
          'detail': {
            'code': 'OPERATION_REJECTED',
            'issues': [
              {'code': 'FUTURE_OCCURRED_DATE', 'field': 'occurredOn'},
            ],
          },
        }),
        const _JsonResponse(503, {
          'detail': {
            'code': 'FINANCE_PERSISTENCE_UNAVAILABLE',
            'issues': <Object?>[],
          },
        }),
      ]);
      final api = _api(adapter);
      final draft = _operationModel(accountId: _accountId);

      final unauthorized = await api.evaluateOperation(
        accessToken: 'access-token',
        draft: draft,
      );
      expect(_failure(unauthorized).kind, FinanceEntryFailureKind.unauthorized);

      final conflict = await api.evaluateOperation(
        accessToken: 'access-token',
        draft: draft,
      );
      expect(_failure(conflict).kind, FinanceEntryFailureKind.conflict);
      expect(_failure(conflict).code, FinanceEntryErrorCode.commandConflict);

      final rejected = await api.evaluateOperation(
        accessToken: 'access-token',
        draft: draft,
      );
      expect(_failure(rejected).kind, FinanceEntryFailureKind.rejected);
      expect(
        _failure(rejected).issues.single.code,
        FinanceIssueCode.futureOccurredDate,
      );

      final unavailable = await api.evaluateOperation(
        accessToken: 'access-token',
        draft: draft,
      );
      expect(
        _failure(unavailable).kind,
        FinanceEntryFailureKind.serviceUnavailable,
      );
    });

    test(
      'rejects unknown fields and oversized responses as malformed',
      () async {
        final unexpected = _accountSetup()..['unexpected'] = true;
        final adapter = _QueueAdapter([
          _JsonResponse(200, unexpected),
          _RawResponse(200, 'x' * (256 * 1024 + 1)),
        ]);
        final api = _api(adapter);

        final unknown = await api.listAccounts(accessToken: 'access-token');
        final oversized = await api.listAccounts(accessToken: 'access-token');

        expect(
          _failure(unknown).kind,
          FinanceEntryFailureKind.malformedResponse,
        );
        expect(
          _failure(oversized).kind,
          FinanceEntryFailureKind.malformedResponse,
        );
      },
    );

    test(
      'maps connection timeout and certificate failures without content',
      () async {
        final adapter = _QueueAdapter([
          const _DioFailure(DioExceptionType.connectionError),
          const _DioFailure(DioExceptionType.receiveTimeout),
          const _DioFailure(DioExceptionType.badCertificate),
        ]);
        final api = _api(adapter);

        final offline = await api.listAccounts(accessToken: 'access-token');
        final timeout = await api.listAccounts(accessToken: 'access-token');
        final unsafe = await api.listAccounts(accessToken: 'access-token');

        expect(_failure(offline).kind, FinanceEntryFailureKind.offline);
        expect(_failure(timeout).kind, FinanceEntryFailureKind.timeout);
        expect(_failure(unsafe).kind, FinanceEntryFailureKind.securityFailure);
      },
    );

    test('reads the caller own profile, with no identifier to pass', () async {
      final adapter = _QueueAdapter([_JsonResponse(200, _profile())]);
      final api = _api(adapter);

      final result = await api.readProfile(accessToken: 'access-token');

      final profile = (result as FinanceEntrySuccess<UserProfile>).value;
      expect(profile.displayName, 'Синтетический Пользователь');
      expect(profile.email, 'owner@example.test');
      expect(profile.account?.currency, 'EUR');
      expect(profile.account?.canonicalTimezone, 'Europe/Berlin');
      expect(profile.account?.openingBalanceOn, '2026-06-01');
      final request = adapter.requests.single;
      expect(request.uri.path, '/api/v1/profile');
      // The subject is the token, never a parameter: asking for someone
      // else's profile has to stay unrepresentable, not merely refused.
      expect(request.uri.queryParameters, isEmpty);
    });

    test('accepts a registered user who has no account yet', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(200, _profile(account: false)),
      ]);
      final api = _api(adapter);

      final result = await api.readProfile(accessToken: 'access-token');

      final profile = (result as FinanceEntrySuccess<UserProfile>).value;
      expect(profile.account, isNull);
    });

    test('refuses money arriving on the profile contract', () async {
      final withBalance = _profile();
      (withBalance['account']! as Map<String, Object?>)['balance'] = '10.00';
      final adapter = _QueueAdapter([_JsonResponse(200, withBalance)]);
      final api = _api(adapter);

      final result = await api.readProfile(accessToken: 'access-token');

      // Failing closed is the point. A second surface quietly reporting a
      // balance is a second thing that can disagree with the projection.
      expect(_failure(result).kind, FinanceEntryFailureKind.malformedResponse);
    });

    test('reads one sentence into a proposal', () async {
      final adapter = _QueueAdapter([_JsonResponse(200, _proposal())]);
      final api = _api(adapter);

      final result = await api.parseOperationText(
        accessToken: 'access-token',
        text: 'Потратил 12,50 на продукты вчера',
        capturedAt: '2026-08-13T09:00:00Z',
        capturedTimezone: 'Europe/Berlin',
      );

      final proposal = (result as FinanceEntrySuccess<OperationProposal>).value;
      expect(proposal.type, FinanceOperationType.expense);
      expect(proposal.amount, '12.50');
      expect(proposal.occurredOn, '2026-08-12');
      expect(proposal.sourceExpression, 'вчера');
      expect(adapter.requests.single.uri.path, '/api/v1/operations/parse');
    });

    test('a proposal without an amount is valid, not malformed', () async {
      final withoutAmount = _proposal();
      (withoutAmount['proposal']! as Map<String, Object?>)['amount'] = null;
      (withoutAmount['proposal']! as Map<String, Object?>)['gaps'] = [
        'AMOUNT_NOT_FOUND',
      ];
      final adapter = _QueueAdapter([_JsonResponse(200, withoutAmount)]);
      final api = _api(adapter);

      final result = await api.parseOperationText(
        accessToken: 'access-token',
        text: 'Купил продукты',
        capturedAt: '2026-08-13T09:00:00Z',
        capturedTimezone: 'Europe/Berlin',
      );

      // Refusing to guess is the designed answer, so it must parse cleanly.
      final proposal = (result as FinanceEntrySuccess<OperationProposal>).value;
      expect(proposal.amount, isNull);
      expect(proposal.gaps, [OperationParseGap.amountNotFound]);
    });

    test('a proposal that tries to be confirmable is refused', () async {
      final confirmable = _proposal();
      (confirmable['proposal']! as Map<String, Object?>)['commandId'] =
          '77777777-7777-4777-8777-777777777777';
      final adapter = _QueueAdapter([_JsonResponse(200, confirmable)]);
      final api = _api(adapter);

      final result = await api.parseOperationText(
        accessToken: 'access-token',
        text: 'Потратил 12',
        capturedAt: '2026-08-13T09:00:00Z',
        capturedTimezone: 'Europe/Berlin',
      );

      // A proposal is powerless by contract. If it ever grows the fields that
      // would make it committable, the client must fail rather than obey.
      expect(_failure(result).kind, FinanceEntryFailureKind.malformedResponse);
    });

    test('an unknown gap from a newer server is dropped, not fatal', () async {
      final unknownGap = _proposal();
      (unknownGap['proposal']! as Map<String, Object?>)['gaps'] = [
        'AMOUNT_NOT_FOUND',
        'MERCHANT_NOT_MATCHED',
      ];
      final adapter = _QueueAdapter([_JsonResponse(200, unknownGap)]);
      final api = _api(adapter);

      final result = await api.parseOperationText(
        accessToken: 'access-token',
        text: 'Потратил 12',
        capturedAt: '2026-08-13T09:00:00Z',
        capturedTimezone: 'Europe/Berlin',
      );

      // A gap is a hint. Refusing to fill the form because of a hint the
      // client does not recognise would be worse than the hint.
      final proposal = (result as FinanceEntrySuccess<OperationProposal>).value;
      expect(proposal.gaps, [OperationParseGap.amountNotFound]);
    });

    test('an empty sentence never reaches the network', () async {
      final adapter = _QueueAdapter([]);
      final api = _api(adapter);

      final result = await api.parseOperationText(
        accessToken: 'access-token',
        text: '   ',
        capturedAt: '2026-08-13T09:00:00Z',
        capturedTimezone: 'Europe/Berlin',
      );

      expect(_failure(result).kind, FinanceEntryFailureKind.invalidInput);
      expect(adapter.requests, isEmpty);
    });

    test('maps an unreadable sentence to a typed failure', () async {
      final adapter = _QueueAdapter([
        const _JsonResponse(503, {
          'detail': {'code': 'TEXT_ENTRY_UNAVAILABLE'},
        }),
      ]);
      final api = _api(adapter);

      final result = await api.parseOperationText(
        accessToken: 'access-token',
        text: 'Потратил 12',
        capturedAt: '2026-08-13T09:00:00Z',
        capturedTimezone: 'Europe/Berlin',
      );

      final failure = _failure(result);
      expect(failure.kind, FinanceEntryFailureKind.serviceUnavailable);
      expect(failure.code, FinanceEntryErrorCode.textEntryUnavailable);
    });

    test('reads and replaces the words that lead to a category', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(200, _keywords(const ['авто', 'машин'])),
        _JsonResponse(200, _keywords(const ['авто'])),
      ]);
      final api = _api(adapter);

      final read = await api.listCategoryKeywords(
        accessToken: 'access-token',
        categoryId: _categoryId,
      );
      final written = await api.replaceCategoryKeywords(
        accessToken: 'access-token',
        categoryId: _categoryId,
        keywords: const ['  Авто '],
      );

      expect((read as FinanceEntrySuccess<CategoryKeywords>).value.keywords, [
        'авто',
        'машин',
      ]);
      expect(
        (written as FinanceEntrySuccess<CategoryKeywords>).value.keywords,
        ['авто'],
      );
      expect(
        adapter.requests.first.uri.path,
        '/api/v1/categories/$_categoryId/keywords',
      );
      expect(adapter.requests.last.method, 'PUT');
      // Normalized before it travels, so one word has one spelling.
      expect((adapter.requests.last.data as Map<String, Object?>)['keywords'], [
        'авто',
      ]);
    });

    test('a malformed keyword never reaches the network', () async {
      final adapter = _QueueAdapter([]);
      final api = _api(adapter);

      final result = await api.replaceCategoryKeywords(
        accessToken: 'access-token',
        categoryId: _categoryId,
        keywords: const ['ав'],
      );

      expect(_failure(result).kind, FinanceEntryFailureKind.invalidInput);
      expect(adapter.requests, isEmpty);
    });

    test('a word claimed by another category is a typed conflict', () async {
      final adapter = _QueueAdapter([
        const _JsonResponse(409, {
          'detail': {
            'code': 'CATEGORY_KEYWORD_TAKEN',
            'keyword': 'авто',
            'owner': 'Транспорт',
          },
        }),
      ]);
      final api = _api(adapter);

      final result = await api.replaceCategoryKeywords(
        accessToken: 'access-token',
        categoryId: _categoryId,
        keywords: const ['авто'],
      );

      final failure = _failure(result);
      expect(failure.kind, FinanceEntryFailureKind.conflict);
      expect(failure.code, FinanceEntryErrorCode.categoryKeywordTaken);
    });

    test(
      'a catalogue error carries its code even without an issue list',
      () async {
        // The catalogue answers with a code and nothing else; requiring an
        // "issues" key here silently threw the code away.
        final adapter = _QueueAdapter([
          const _JsonResponse(409, {
            'detail': {'code': 'CATEGORY_NAME_TAKEN'},
          }),
        ]);
        final api = _api(adapter);

        final result = await api.createCategory(
          accessToken: 'access-token',
          command: const CreateCategoryCommand(
            name: 'Кофе',
            direction: FinanceOperationType.expense,
          ),
        );

        expect(_failure(result).code, FinanceEntryErrorCode.categoryNameTaken);
      },
    );

    test('maps an unavailable profile to a typed failure', () async {
      final adapter = _QueueAdapter([
        const _JsonResponse(503, {
          'detail': {'code': 'PROFILE_UNAVAILABLE'},
        }),
      ]);
      final api = _api(adapter);

      final result = await api.readProfile(accessToken: 'access-token');

      final failure = _failure(result);
      expect(failure.kind, FinanceEntryFailureKind.serviceUnavailable);
      expect(failure.code, FinanceEntryErrorCode.profileUnavailable);
    });
  });

  group('recurring planned costs (ADR 0025)', () {
    test('a created rule reports the dates it materialised', () async {
      final adapter = _QueueAdapter([_JsonResponse(201, _recurrenceCreated())]);
      final api = _api(adapter);

      final result = await api.createPlannedCostRecurrence(
        accessToken: 'access-token',
        draft: _recurrenceDraft(),
      );

      final created =
          (result as FinanceEntrySuccess<PlannedCostRecurrenceCreated>).value;
      expect(created.idempotentReplay, isFalse);
      expect(created.recurrence.dayOfMonth, 31);
      // February is in the answer, which is where a user sees the clamp.
      expect(created.occurrences, ['2026-01-31', '2026-02-28', '2026-03-31']);
      expect(
        adapter.requests.single.uri.path,
        '/api/v1/planned-cost-recurrences',
      );
    });

    test('a replay flag that disagrees with the status is refused', () async {
      final replayed = _recurrenceCreated();
      replayed['idempotentReplay'] = true;
      final adapter = _QueueAdapter([_JsonResponse(201, replayed)]);
      final api = _api(adapter);

      final result = await api.createPlannedCostRecurrence(
        accessToken: 'access-token',
        draft: _recurrenceDraft(),
      );

      // 201 means first acceptance and 200 means replay. A server claiming
      // both at once is not something to interpret generously.
      expect(_failure(result).kind, FinanceEntryFailureKind.malformedResponse);
    });

    test('a rule that does not match the command is refused', () async {
      final mismatched = _recurrenceCreated();
      (mismatched['recurrence']! as Map<String, Object?>)['dayOfMonth'] = 15;
      final adapter = _QueueAdapter([_JsonResponse(201, mismatched)]);
      final api = _api(adapter);

      final result = await api.createPlannedCostRecurrence(
        accessToken: 'access-token',
        draft: _recurrenceDraft(),
      );

      expect(_failure(result).kind, FinanceEntryFailureKind.malformedResponse);
    });

    test('an unknown key in the rule is refused rather than ignored', () async {
      final widened = _recurrenceCreated();
      (widened['recurrence']! as Map<String, Object?>)['weekday'] = 'monday';
      final adapter = _QueueAdapter([_JsonResponse(201, widened)]);
      final api = _api(adapter);

      final result = await api.createPlannedCostRecurrence(
        accessToken: 'access-token',
        draft: _recurrenceDraft(),
      );

      expect(_failure(result).kind, FinanceEntryFailureKind.malformedResponse);
    });

    test('a wrong category is a typed refusal, not a bare error', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(422, {
          'detail': {
            'code': 'RECURRENCE_REJECTED',
            'issues': [
              {'code': 'CATEGORY_DIRECTION_MISMATCH', 'field': 'categoryId'},
            ],
          },
        }),
      ]);
      final api = _api(adapter);

      final result = await api.createPlannedCostRecurrence(
        accessToken: 'access-token',
        draft: _recurrenceDraft(),
      );

      final failure = _failure(result);
      expect(failure.code, FinanceEntryErrorCode.recurrenceRejected);
      expect(
        failure.plannedCostIssues.single.code,
        PlannedCostIssueCode.categoryDirectionMismatch,
      );
    });

    test('ending a series reports what it withdrew', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(200, {
          'schemaVersion': '1',
          'idempotentReplay': false,
          'recurrence': _recurrence(status: 'ended'),
          'cancelledOccurrences': 2,
        }),
      ]);
      final api = _api(adapter);

      final result = await api.endPlannedCostRecurrence(
        accessToken: 'access-token',
        recurrenceId: _recurrenceId,
        command: const EndPlannedCostRecurrenceCommand(
          commandId: _recurrenceCommandId,
          requestedAt: '2026-01-15T23:30:00Z',
        ),
      );

      final ended =
          (result as FinanceEntrySuccess<PlannedCostRecurrenceEnded>).value;
      expect(ended.cancelledOccurrences, 2);
      expect(ended.recurrence.status, PlannedCostRecurrenceStatus.ended);
    });

    test('a rule reported still active after ending is refused', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(200, {
          'schemaVersion': '1',
          'idempotentReplay': false,
          'recurrence': _recurrence(),
          'cancelledOccurrences': 0,
        }),
      ]);
      final api = _api(adapter);

      final result = await api.endPlannedCostRecurrence(
        accessToken: 'access-token',
        recurrenceId: _recurrenceId,
        command: const EndPlannedCostRecurrenceCommand(
          commandId: _recurrenceCommandId,
          requestedAt: '2026-01-15T23:30:00Z',
        ),
      );

      // Otherwise the screen keeps offering to end something already ended.
      expect(_failure(result).kind, FinanceEntryFailureKind.malformedResponse);
    });

    test('the listing links a rule to the instances it owns', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(200, {
          'schemaVersion': '1',
          'recurrences': [
            {
              'recurrence': _recurrence(),
              'upcoming': [
                {
                  'plannedCostId': _recurrenceInstanceId,
                  'plannedOn': '2026-02-28',
                },
              ],
            },
          ],
        }),
      ]);
      final api = _api(adapter);

      final result = await api.listPlannedCostRecurrences(
        accessToken: 'access-token',
      );

      final listed =
          (result as FinanceEntrySuccess<PlannedCostRecurrenceList>).value;
      expect(
        listed.recurrences.single.upcoming.single.plannedCostId,
        _recurrenceInstanceId,
      );
    });

    test('the planned cost response is still frozen', () async {
      // The link travels on the rule listing precisely because it cannot
      // travel here: the installed client parses a plan with a closed key set,
      // so a new key would stop it loading rather than degrade it.
      expect(
        () => PlannedCost.fromJson({
          'plannedCostId': _recurrenceInstanceId,
          'userId': '11111111-1111-4111-8111-111111111111',
          'accountId': _plannedAccountId,
          'commandId': _recurrenceCommandId,
          'amount': '800.00',
          'currency': 'EUR',
          'title': 'Аренда',
          'category': null,
          'plannedOn': '2026-02-28',
          'status': 'planned',
          'isDue': false,
          'confirmedOperationId': null,
          'createdAt': '2026-01-15T23:30:00Z',
          'updatedAt': '2026-01-15T23:30:00Z',
          'recurrenceId': _recurrenceId,
        }),
        throwsFormatException,
      );
    });
  });

  group("asking for one's own account to be erased (ADR 0030)", () {
    test('answers when the erasure will happen', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(202, const {
          'schemaVersion': '1',
          'deletionDueAt': '2026-10-23T12:00:00Z',
        }),
      ]);

      final result = await _api(adapter).requestAccountDeletion(
        accessToken: 'access-token',
        password: 'synthetic-password',
      );

      expect(
        (result as FinanceEntrySuccess<DateTime>).value,
        DateTime.utc(2026, 10, 23, 12),
      );
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v1/account/deletion');
      expect(request.data, {
        'schemaVersion': '1',
        'password': 'synthetic-password',
      });
    });

    test(
      'a wrong password is a refusal of the request, not the session',
      () async {
        final adapter = _QueueAdapter([
          _JsonResponse(403, const {
            'detail': {'code': 'PASSWORD_REJECTED'},
          }),
        ]);

        final result = await _api(adapter).requestAccountDeletion(
          accessToken: 'access-token',
          password: 'wrong',
        );

        final failure = (result as FinanceEntryFailureResult<DateTime>).failure;
        expect(failure.kind, FinanceEntryFailureKind.rejected);
        expect(failure.code, FinanceEntryErrorCode.passwordRejected);
      },
    );

    test('any other refusal shape fails closed', () async {
      final adapter = _QueueAdapter([
        _JsonResponse(403, const {
          'detail': {'code': 'PROFILE_UNAVAILABLE'},
        }),
        _JsonResponse(202, const {
          'schemaVersion': '1',
          'deletionDueAt': '2026-10-23T12:00:00Z',
          'erasedAt': null,
        }),
        _JsonResponse(202, const {
          'schemaVersion': '1',
          'deletionDueAt': 'next week',
        }),
      ]);
      final api = _api(adapter);

      for (var attempt = 0; attempt < 3; attempt += 1) {
        final result = await api.requestAccountDeletion(
          accessToken: 'access-token',
          password: 'synthetic-password',
        );
        expect(
          (result as FinanceEntryFailureResult<DateTime>).failure.kind,
          FinanceEntryFailureKind.malformedResponse,
          reason: 'attempt $attempt',
        );
      }
    });
  });
}

const _recurrenceId = '99999999-9999-4999-8999-999999999999';
const _recurrenceCommandId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _recurrenceInstanceId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _plannedAccountId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

PlannedCostRecurrenceDraft _recurrenceDraft() {
  return const PlannedCostRecurrenceDraft(
    commandId: _recurrenceCommandId,
    accountId: _plannedAccountId,
    amount: '800.00',
    currency: 'EUR',
    title: 'Аренда',
    dayOfMonth: 31,
    startsOn: '2026-01-01',
    requestedAt: '2026-01-15T23:30:00Z',
  );
}

Map<String, Object?> _recurrence({String status = 'active'}) {
  return <String, Object?>{
    'recurrenceId': _recurrenceId,
    'userId': '11111111-1111-4111-8111-111111111111',
    'accountId': _plannedAccountId,
    'commandId': _recurrenceCommandId,
    'amount': '800.00',
    'currency': 'EUR',
    'title': 'Аренда',
    'category': null,
    'categoryId': null,
    'frequency': 'monthly',
    'dayOfMonth': 31,
    'startsOn': '2026-01-01',
    'endsOn': null,
    'status': status,
    'createdAt': '2026-01-15T23:30:00Z',
    'updatedAt': '2026-01-15T23:30:00Z',
  };
}

Map<String, Object?> _recurrenceCreated() {
  return <String, Object?>{
    'schemaVersion': '1',
    'idempotentReplay': false,
    'recurrence': _recurrence(),
    'occurrences': ['2026-01-31', '2026-02-28', '2026-03-31'],
  };
}

const _categoryId = '88888888-8888-4888-8888-888888888888';

Map<String, Object?> _keywords(List<String> words) {
  return <String, Object?>{
    'schemaVersion': '1',
    'categoryId': _categoryId,
    'keywords': words,
  };
}

Map<String, Object?> _proposal() {
  return <String, Object?>{
    'schemaVersion': '1',
    'proposal': <String, Object?>{
      'type': 'expense',
      'amount': '12.50',
      'currency': 'EUR',
      'occurredOn': '2026-08-12',
      'sourceExpression': 'вчера',
      'categoryId': '66666666-6666-4666-8666-666666666666',
      'category': 'продукты',
      'gaps': <Object?>[],
    },
  };
}

Map<String, Object?> _profile({bool account = true}) {
  return <String, Object?>{
    'schemaVersion': '1',
    'user': <String, Object?>{
      'id': '44444444-4444-4444-8444-444444444444',
      'displayName': 'Синтетический Пользователь',
      'email': 'owner@example.test',
    },
    'account': account
        ? <String, Object?>{
            'id': '55555555-5555-4555-8555-555555555555',
            'currency': 'EUR',
            'canonicalTimezone': 'Europe/Berlin',
            'openingBalanceOn': '2026-06-01',
          }
        : null,
  };
}

FinanceEntryApi _api(_QueueAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  addTearDown(() => dio.close(force: true));
  return FinanceEntryApi(
    dio: dio,
    baseUri: Uri.parse('https://example.test/backend/'),
    requestIdFactory: () => 'req_finance_test',
  );
}

FinanceTimezoneCommand _timezoneCommand() => FinanceTimezoneCommand(
  commandId: '22222222-2222-4222-8222-222222222222',
  accountId: '11111111-1111-4111-8111-111111111111',
  canonicalTimezone: 'Europe/Kyiv',
  requestedAt: DateTime.utc(2026, 9, 2, 10, 30),
);

FinanceEntryFailure _failure<T>(FinanceEntryResult<T> result) =>
    (result as FinanceEntryFailureResult<T>).failure;

FinanceOperationDraft _operationModel({
  required String? accountId,
  String amount = '35.00',
}) {
  return FinanceOperationDraft(
    commandId: _operationCommandId,
    type: FinanceOperationType.expense,
    amount: amount,
    currency: 'EUR',
    accountId: accountId,
    category: 'Groceries',
    merchant: 'Synthetic shop',
    capturedAt: '2026-07-28T12:00:00Z',
    capturedTimezone: 'Europe/Berlin',
    sourceExpression: null,
    occurredOn: '2026-07-28',
    occurredAt: null,
    source: FinanceOperationSource.manualText,
  );
}

Map<String, Object?> _accountDraft({String openingBalance = '1000'}) => {
  'schemaVersion': '1',
  'commandId': _accountCommandId,
  'name': 'Main account',
  'currency': 'EUR',
  'openingBalance': openingBalance,
  'openingBalanceOn': '2026-07-28',
  'canonicalTimezone': 'Europe/Berlin',
};

Map<String, Object?> _operationDraft({
  required String? accountId,
  String amount = '35',
}) => {
  'schemaVersion': '1',
  'commandId': _operationCommandId,
  'type': 'expense',
  'amount': amount,
  'currency': 'EUR',
  'accountId': accountId,
  'category': 'Groceries',
  'merchant': 'Synthetic shop',
  'capturedAt': '2026-07-28T12:00:00Z',
  'capturedTimezone': 'Europe/Berlin',
  'sourceExpression': null,
  'dateResolverVersion': 'calendar-relative-v1',
  'occurredOn': '2026-07-28',
  'occurredAt': null,
  'source': 'manual_text',
};

Map<String, Object?> _evaluation({
  required Map<String, Object?> draft,
  required String decision,
  List<Map<String, Object?>> issues = const [],
}) => {
  'schemaVersion': '1',
  'decision': decision,
  'draft': draft,
  'draftHash': decision == 'NEEDS_CONFIRMATION' ? _draftHash : null,
  'issues': issues,
};

FinanceBaselineDraft _baselineModel({String openingBalanceOn = '2026-01-01'}) =>
    FinanceBaselineDraft(
      commandId: _baselineCommandId,
      accountId: _accountId,
      openingBalanceOn: openingBalanceOn,
    );

FinanceBaselineCommitCommand _baselineCommand() =>
    FinanceBaselineCommitCommand.fromReview(
      review: FinanceBaselineNeedsConfirmation(
        draft: _baselineModel(),
        currentOpeningBalanceOn: '2026-07-28',
        earliestOperationOn: null,
        draftHash: 'a' * 64,
      ),
      confirmedAt: DateTime.utc(2026, 8, 2, 12),
    );

Map<String, Object?> _baselineDraft({String openingBalanceOn = '2026-01-01'}) =>
    {
      'schemaVersion': '1',
      'commandId': _baselineCommandId,
      'accountId': _accountId,
      'openingBalanceOn': openingBalanceOn,
    };

Map<String, Object?> _baselineEvaluation({
  required String decision,
  List<Map<String, Object?>> issues = const [],
}) => {
  'schemaVersion': '1',
  'decision': decision,
  'draft': _baselineDraft(),
  'draftHash': decision == 'REJECT' ? null : 'a' * 64,
  'currentOpeningBalanceOn': '2026-07-28',
  'earliestOperationOn': null,
  'issues': issues,
};

Map<String, Object?> _baselineCommit({String previous = '2026-07-28'}) => {
  'schemaVersion': '1',
  'decision': 'ACCEPT',
  'idempotentReplay': false,
  'previousOpeningBalanceOn': previous,
  'account': {
    'accountId': _accountId,
    'userId': _userId,
    'commandId': _accountCommandId,
    'name': 'Main account',
    'currency': 'EUR',
    'openingBalance': '1000',
    'openingBalanceOn': '2026-01-01',
    'openingTimezone': 'Europe/Berlin',
    'status': 'active',
    'isDefault': true,
    'confirmedAt': '2026-07-28T12:01:00Z',
    'createdAt': '2026-07-28T12:01:01Z',
  },
};

Map<String, Object?> _accountSetup() => {
  'schemaVersion': '1',
  'canonicalTimezone': 'Europe/Berlin',
  'timezoneRevision': 1,
  'accounts': [
    {
      'accountId': _accountId,
      'userId': _userId,
      'commandId': _accountCommandId,
      'name': 'Main account',
      'currency': 'EUR',
      'openingBalance': '1000',
      'openingBalanceOn': '2026-07-28',
      'openingTimezone': 'Europe/Berlin',
      'status': 'active',
      'isDefault': true,
      'confirmedAt': '2026-07-28T12:01:00Z',
      'createdAt': '2026-07-28T12:01:01Z',
    },
  ],
};

Map<String, Object?> _accountCommit({
  required Map<String, Object?> draft,
  required String confirmedAt,
}) => {
  'schemaVersion': '1',
  'decision': 'ACCEPT',
  'idempotentReplay': false,
  'canonicalTimezone': 'Europe/Berlin',
  'timezoneRevision': 1,
  'account': {
    'accountId': _accountId,
    'userId': _userId,
    'commandId': draft['commandId'],
    'name': draft['name'],
    'currency': draft['currency'],
    'openingBalance': draft['openingBalance'],
    'openingBalanceOn': draft['openingBalanceOn'],
    'openingTimezone': draft['canonicalTimezone'],
    'status': 'active',
    'isDefault': true,
    'confirmedAt': confirmedAt,
    'createdAt': '2026-07-28T12:01:01Z',
  },
};

Map<String, Object?> _operationCommit({
  required Map<String, Object?> draft,
  required String confirmedAt,
}) {
  final operationDraft = Map<String, Object?>.from(draft)
    ..remove('schemaVersion');
  return {
    'schemaVersion': '1',
    'decision': 'ACCEPT',
    'idempotentReplay': false,
    'operation': {
      'operationId': _operationId,
      'userId': _userId,
      ...operationDraft,
      'status': 'confirmed',
      'confirmedAt': confirmedAt,
      'createdAt': '2026-07-28T12:01:01Z',
    },
  };
}

const _accountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _operationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _userId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _accountCommandId = '11111111-1111-4111-8111-111111111111';
const _baselineCommandId = '77777777-7777-4777-8777-777777777777';
const _operationCommandId = '22222222-2222-4222-8222-222222222222';
const _draftHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

sealed class _QueuedResponse {
  const _QueuedResponse();
}

final class _JsonResponse extends _QueuedResponse {
  const _JsonResponse(this.statusCode, this.json);
  final int statusCode;
  final Map<String, Object?> json;
}

final class _RawResponse extends _QueuedResponse {
  const _RawResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

final class _DioFailure extends _QueuedResponse {
  const _DioFailure(this.type);
  final DioExceptionType type;
}

final class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(List<_QueuedResponse> responses)
    : _responses = List.of(responses);

  final List<_QueuedResponse> _responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = _responses.removeAt(0);
    return switch (response) {
      _JsonResponse(:final statusCode, :final json) => _body(
        statusCode,
        jsonEncode(json),
      ),
      _RawResponse(:final statusCode, :final body) => _body(statusCode, body),
      _DioFailure(:final type) => throw DioException(
        requestOptions: options,
        type: type,
      ),
    };
  }

  ResponseBody _body(int statusCode, String body) {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        Headers.contentLengthHeader: [utf8.encode(body).length.toString()],
        'x-request-id': ['req_server_finance'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
