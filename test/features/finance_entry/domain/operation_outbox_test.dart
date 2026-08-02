import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/operation_outbox.dart';

void main() {
  test('confirmed operation command has a strict lossless decoder', () {
    final command = _command();

    final decoded = FinanceOperationCommitCommand.fromJson(command.toJson());

    expect(decoded.toJson(), command.toJson());
    expect(decoded.review.draft.amount, '731.42');
    expect(decoded.review.draft.merchant, 'Synthetic Merchant Marker');

    final additive = Map<String, Object?>.from(command.toJson())
      ..['unexpected'] = true;
    expect(
      () => FinanceOperationCommitCommand.fromJson(additive),
      throwsFormatException,
    );
  });

  test('confirmed operation decoder rejects confirmation before capture', () {
    final json = Map<String, Object?>.from(_command().toJson())
      ..['confirmedAt'] = '2026-07-29T09:59:59Z';

    expect(
      () => FinanceOperationCommitCommand.fromJson(json),
      throwsFormatException,
    );
  });

  test('failure classifier keeps ambiguity and security separate', () {
    expect(
      classifyOperationOutboxFailure(
        FinanceEntryFailure(
          kind: FinanceEntryFailureKind.unknown,
          requestId: 'req_synthetic',
        ),
      ),
      isA<OperationOutboxFailureClassification>()
          .having(
            (value) => value.disposition,
            'disposition',
            OperationOutboxFailureDisposition.retryable,
          )
          .having(
            (value) => value.code,
            'code',
            OperationOutboxErrorCode.ambiguousResult,
          ),
    );
    expect(
      classifyOperationOutboxFailure(
        FinanceEntryFailure(
          kind: FinanceEntryFailureKind.securityFailure,
          requestId: 'req_synthetic',
        ),
      ),
      isA<OperationOutboxFailureClassification>()
          .having(
            (value) => value.disposition,
            'disposition',
            OperationOutboxFailureDisposition.permanent,
          )
          .having(
            (value) => value.code,
            'code',
            OperationOutboxErrorCode.securityBlocked,
          ),
    );
  });

  test('interrupted delivery remains retryable with its exact code', () {
    expect(
      classifyOperationOutboxFailure(
        FinanceEntryFailure(
          kind: FinanceEntryFailureKind.interrupted,
          requestId: 'req_synthetic_interrupted',
        ),
      ),
      isA<OperationOutboxFailureClassification>()
          .having(
            (value) => value.disposition,
            'disposition',
            OperationOutboxFailureDisposition.retryable,
          )
          .having(
            (value) => value.code,
            'code',
            OperationOutboxErrorCode.interrupted,
          ),
    );
  });

  test('retry delay is bounded and jittered', () {
    expect(
      operationOutboxRetryDelay(attemptCount: 1, jitterUnit: 0),
      const Duration(milliseconds: 1600),
    );
    expect(
      operationOutboxRetryDelay(attemptCount: 1, jitterUnit: 1),
      const Duration(milliseconds: 2400),
    );
    expect(
      operationOutboxRetryDelay(attemptCount: 100, jitterUnit: 0.5),
      const Duration(minutes: 5),
    );
  });
}

FinanceOperationCommitCommand _command() {
  final draft = FinanceOperationDraft.fromJson(const <String, Object?>{
    'schemaVersion': '1',
    'commandId': '44444444-4444-4444-8444-444444444444',
    'type': 'expense',
    'amount': '731.42',
    'currency': 'EUR',
    'accountId': '22222222-2222-4222-8222-222222222222',
    'category': 'Synthetic Category Marker',
    'merchant': 'Synthetic Merchant Marker',
    'capturedAt': '2026-07-29T10:00:00Z',
    'capturedTimezone': 'Europe/Berlin',
    'sourceExpression': 'synthetic source expression marker',
    'dateResolverVersion': 'calendar-relative-v1',
    'occurredOn': '2026-07-28',
    'occurredAt': null,
    'source': 'manual_text',
  });
  return FinanceOperationCommitCommand.fromReview(
    review: FinanceOperationNeedsConfirmation(
      draft: draft,
      draftHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
    confirmedAt: DateTime.utc(2026, 7, 29, 10, 1),
  );
}
