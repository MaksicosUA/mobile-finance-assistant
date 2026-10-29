import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/canonical_timezone.dart';
import '../../auth/application/auth_controller.dart';
import '../../voice_entry/application/waiting_phrases_controller.dart';
import '../../voice_entry/domain/waiting_phrase.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'finance_entry_controller.dart';

final textEntryControllerProvider =
    NotifierProvider.autoDispose<TextEntryController, TextEntryState>(
      TextEntryController.new,
    );

sealed class TextEntryState {
  const TextEntryState();
}

final class TextEntryIdle extends TextEntryState {
  const TextEntryIdle();
}

final class TextEntryParsing extends TextEntryState {
  const TextEntryParsing();
}

@immutable
final class TextEntryParsed extends TextEntryState {
  const TextEntryParsed(this.proposal);

  final OperationProposal proposal;
}

@immutable
final class TextEntryFailed extends TextEntryState {
  const TextEntryFailed(this.failure);

  final FinanceEntryFailure failure;
}

/// Turns one written sentence into a proposal that fills the entry form.
///
/// It never records anything. The proposal has no command id and no
/// confirmation hash, so the only way to a real operation stays the ordinary
/// evaluate → review → confirm path the form already runs (ADR 0022).
class TextEntryController extends Notifier<TextEntryState> {
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  @override
  TextEntryState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    return const TextEntryIdle();
  }

  /// Forgets the last proposal so the same sentence can be read again.
  void reset() {
    _requestGeneration += 1;
    _requestInFlight = false;
    state = const TextEntryIdle();
  }

  /// Reads [text] as of now — or, for a [phrase] said earlier, as of the
  /// moment it was said, so «вчера» keeps meaning the day before it was said
  /// (ADR 0032). Once the server has answered about that phrase it stops
  /// waiting on the phone.
  Future<void> parse(String text, {WaitingPhrase? phrase}) async {
    if (_requestInFlight) return;
    final sentence = text.trim();
    if (sentence.isEmpty || sentence.length > maximumEntryTextLength) {
      state = TextEntryFailed(
        FinanceEntryFailure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: 'req_local_text_entry_invalid',
        ),
      );
      return;
    }
    final requestGeneration = _beginRequest();
    state = const TextEntryParsing();
    // Read before any await: this controller may be gone by the time the
    // server answers, and the phrase must stop waiting all the same.
    final waiting = phrase == null
        ? null
        : ref.read(waitingPhrasesProvider.notifier);
    try {
      final (capturedAt, capturedTimezone) = await _moment(phrase);
      if (!_isCurrentRequest(requestGeneration)) return;
      final result = await _repository.parseOperationText(
        text: sentence,
        capturedAt: capturedAt,
        // The day the sentence means is resolved server-side in this zone,
        // never from the phone's idea of the calendar (ADR 0007).
        capturedTimezone: capturedTimezone,
      );
      if (phrase != null && _serverHasRead(result)) {
        unawaited(waiting!.forget(phrase.id));
      }
      if (!_isCurrentRequest(requestGeneration)) return;
      state = switch (result) {
        FinanceEntrySuccess(:final value) => TextEntryParsed(value),
        FinanceEntryFailureResult(:final failure) => TextEntryFailed(failure),
      };
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = TextEntryFailed(
          FinanceEntryFailure(
            kind: FinanceEntryFailureKind.unknown,
            requestId: 'req_local_text_entry_unknown',
          ),
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  /// Reads the same sentence as an exchange, for the screen that moves money
  /// between wallets.
  ///
  /// Kept out of [state] on purpose: this screen's state describes the form in
  /// front of the person, and a transfer is a different screen's business. A
  /// null answer — the sentence is not an exchange after all, or the request
  /// failed — means the offer simply does not open anything.
  Future<TransferProposal?> readTransfer(
    String text, {
    WaitingPhrase? phrase,
  }) async {
    final sentence = text.trim();
    if (sentence.isEmpty || sentence.length > maximumEntryTextLength) {
      return null;
    }
    try {
      final (capturedAt, capturedTimezone) = await _moment(phrase);
      final result = await _repository.parseTransferText(
        text: sentence,
        capturedAt: capturedAt,
        capturedTimezone: capturedTimezone,
      );
      return switch (result) {
        FinanceEntrySuccess(:final value) => value,
        FinanceEntryFailureResult() => null,
      };
    } on Object {
      return null;
    }
  }

  /// When the sentence was said: the kept moment of a [phrase], or now.
  Future<(String, String)> _moment(WaitingPhrase? phrase) async {
    if (phrase != null) {
      return (phrase.saidAt.toIso8601String(), phrase.saidInTimezone);
    }
    final capture = await ref
        .read(financeCaptureContextSourceProvider)
        .capture(canonicalTimezone: ref.read(canonicalTimezoneProvider));
    return (capture.capturedAtUtc.toIso8601String(), capture.capturedTimezone);
  }

  /// Whether the server has said what it makes of the words: a proposal, or a
  /// refusal no retry would change. Anything else — no connection, a server
  /// that could not answer, an ended session — leaves the phrase waiting.
  static bool _serverHasRead(FinanceEntryResult<OperationProposal> result) =>
      switch (result) {
        FinanceEntrySuccess() => true,
        FinanceEntryFailureResult(:final failure) =>
          failure.kind == FinanceEntryFailureKind.invalidInput ||
              failure.kind == FinanceEntryFailureKind.rejected,
      };

  int _beginRequest() {
    _requestInFlight = true;
    _requestGeneration += 1;
    return _requestGeneration;
  }

  bool _isCurrentRequest(int requestGeneration) =>
      ref.mounted && requestGeneration == _requestGeneration;

  void _endRequest(int requestGeneration) {
    if (_isCurrentRequest(requestGeneration)) _requestInFlight = false;
  }
}
