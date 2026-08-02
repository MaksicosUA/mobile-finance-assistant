import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/operation_outbox_codec.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/operation_outbox.dart';

void main() {
  test(
    'AES-GCM roundtrip authenticates payload and every metadata field',
    () async {
      final codec = await OperationOutboxCodec.create(
        Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
      );
      addTearDown(codec.dispose);
      final command = _command();
      final metadata = await _metadata(codec);
      final payload = OperationOutboxPayload(
        principalScopeId: _principal,
        financeAccountId: _accountId,
        commandId: _commandId,
        confirmedCommandSha256: await codec.confirmedCommandDigest(command),
        confirmedCommand: command,
        serverOperationId: null,
      );

      final encrypted = await codec.encrypt(
        metadata: metadata,
        payload: payload,
      );
      final decoded = await codec.decrypt(
        metadata: metadata,
        nonce: encrypted.nonce,
        ciphertext: encrypted.ciphertext,
        mac: encrypted.mac,
      );

      expect(decoded.principalScopeId, _principal);
      expect(decoded.confirmedCommand?.toJson(), command.toJson());
      expect(metadata.principalTag, isNot(contains(_principal)));
      expect(metadata.financeAccountTag, isNot(contains(_accountId)));

      final changedMetadata = OperationOutboxEnvelopeMetadata(
        localId: metadata.localId,
        principalTag: metadata.principalTag,
        financeAccountTag: metadata.financeAccountTag,
        commandTag: metadata.commandTag,
        state: OperationOutboxState.syncing,
        transitionSequence: metadata.transitionSequence,
        createdAtEpochMs: metadata.createdAtEpochMs,
        stateChangedAtEpochMs: metadata.stateChangedAtEpochMs,
        nextAttemptAtEpochMs: metadata.nextAttemptAtEpochMs,
        attemptCount: metadata.attemptCount,
      );
      await expectLater(
        codec.decrypt(
          metadata: changedMetadata,
          nonce: encrypted.nonce,
          ciphertext: encrypted.ciphertext,
          mac: encrypted.mac,
        ),
        throwsA(
          isA<OperationOutboxException>().having(
            (error) => error.code,
            'code',
            OperationOutboxErrorCode.corruptPayload,
          ),
        ),
      );

      final tampered = Uint8List.fromList(encrypted.ciphertext)
        ..[0] = encrypted.ciphertext[0] ^ 1;
      await expectLater(
        codec.decrypt(
          metadata: metadata,
          nonce: encrypted.nonce,
          ciphertext: tampered,
          mac: encrypted.mac,
        ),
        throwsA(
          isA<OperationOutboxException>().having(
            (error) => error.code,
            'code',
            OperationOutboxErrorCode.corruptPayload,
          ),
        ),
      );

      final invalidPendingMetadata = OperationOutboxEnvelopeMetadata(
        localId: metadata.localId,
        principalTag: metadata.principalTag,
        financeAccountTag: metadata.financeAccountTag,
        commandTag: metadata.commandTag,
        state: metadata.state,
        transitionSequence: metadata.transitionSequence,
        createdAtEpochMs: metadata.createdAtEpochMs,
        stateChangedAtEpochMs: metadata.stateChangedAtEpochMs,
        nextAttemptAtEpochMs: metadata.nextAttemptAtEpochMs,
        attemptCount: metadata.attemptCount,
        homeConvergencePending: true,
      );
      await expectLater(
        codec.encrypt(metadata: invalidPendingMetadata, payload: payload),
        throwsA(
          isA<OperationOutboxException>().having(
            (error) => error.code,
            'code',
            OperationOutboxErrorCode.corruptPayload,
          ),
        ),
      );
    },
  );

  test('home convergence flag is authenticated in synced metadata', () async {
    final codec = await OperationOutboxCodec.create(
      Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
    );
    addTearDown(codec.dispose);
    final command = _command();
    final pendingMetadata = await _metadata(codec);
    final syncedAt = DateTime.utc(2026, 7, 29, 10, 2).millisecondsSinceEpoch;
    final syncedMetadata = OperationOutboxEnvelopeMetadata(
      localId: pendingMetadata.localId,
      principalTag: pendingMetadata.principalTag,
      financeAccountTag: pendingMetadata.financeAccountTag,
      commandTag: pendingMetadata.commandTag,
      state: OperationOutboxState.synced,
      transitionSequence: 1,
      createdAtEpochMs: pendingMetadata.createdAtEpochMs,
      stateChangedAtEpochMs: syncedAt,
      syncedAtEpochMs: syncedAt,
      attemptCount: 1,
      homeConvergencePending: true,
    );
    final tombstone = OperationOutboxPayload(
      principalScopeId: _principal,
      financeAccountId: _accountId,
      commandId: _commandId,
      confirmedCommandSha256: await codec.confirmedCommandDigest(command),
      confirmedCommand: null,
      serverOperationId: _operationId,
    );
    final encrypted = await codec.encrypt(
      metadata: syncedMetadata,
      payload: tombstone,
    );

    final decoded = await codec.decrypt(
      metadata: syncedMetadata,
      nonce: encrypted.nonce,
      ciphertext: encrypted.ciphertext,
      mac: encrypted.mac,
    );
    expect(decoded.serverOperationId, _operationId);

    final clearedMetadata = OperationOutboxEnvelopeMetadata(
      localId: syncedMetadata.localId,
      principalTag: syncedMetadata.principalTag,
      financeAccountTag: syncedMetadata.financeAccountTag,
      commandTag: syncedMetadata.commandTag,
      state: syncedMetadata.state,
      transitionSequence: syncedMetadata.transitionSequence,
      createdAtEpochMs: syncedMetadata.createdAtEpochMs,
      stateChangedAtEpochMs: syncedMetadata.stateChangedAtEpochMs,
      syncedAtEpochMs: syncedMetadata.syncedAtEpochMs,
      attemptCount: syncedMetadata.attemptCount,
      homeConvergencePending: false,
    );
    await expectLater(
      codec.decrypt(
        metadata: clearedMetadata,
        nonce: encrypted.nonce,
        ciphertext: encrypted.ciphertext,
        mac: encrypted.mac,
      ),
      throwsA(
        isA<OperationOutboxException>().having(
          (error) => error.code,
          'code',
          OperationOutboxErrorCode.corruptPayload,
        ),
      ),
    );
  });
}

const _principal = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _commandId = '44444444-4444-4444-8444-444444444444';
const _operationId = '55555555-5555-4555-8555-555555555555';

Future<OperationOutboxEnvelopeMetadata> _metadata(
  OperationOutboxCodec codec,
) async => OperationOutboxEnvelopeMetadata(
  localId: '77777777-7777-4777-8777-777777777777',
  principalTag: await codec.principalTag(_principal),
  financeAccountTag: await codec.financeAccountTag(_accountId),
  commandTag: await codec.commandTag(
    principalScopeId: _principal,
    commandId: _commandId,
  ),
  state: OperationOutboxState.pending,
  transitionSequence: 0,
  createdAtEpochMs: DateTime.utc(2026, 7, 29, 10).millisecondsSinceEpoch,
  stateChangedAtEpochMs: DateTime.utc(2026, 7, 29, 10).millisecondsSinceEpoch,
  nextAttemptAtEpochMs: DateTime.utc(2026, 7, 29, 10).millisecondsSinceEpoch,
  attemptCount: 0,
);

FinanceOperationCommitCommand _command() {
  final draft = FinanceOperationDraft.fromJson(const <String, Object?>{
    'schemaVersion': '1',
    'commandId': _commandId,
    'type': 'expense',
    'amount': '731.42',
    'currency': 'EUR',
    'accountId': _accountId,
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
