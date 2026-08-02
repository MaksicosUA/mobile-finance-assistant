import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_api.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';

void main() {
  group('FinanceEntryApi', () {
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
  });
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
