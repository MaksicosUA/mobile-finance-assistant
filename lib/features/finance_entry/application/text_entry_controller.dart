import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../auth/application/auth_controller.dart';
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

  Future<void> parse(String text) async {
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
    try {
      final capture = await ref
          .read(financeCaptureContextSourceProvider)
          .capture(canonicalTimezone: configuredHomeApiTimezone);
      if (!_isCurrentRequest(requestGeneration)) return;
      final result = await _repository.parseOperationText(
        text: sentence,
        capturedAt: capture.capturedAtUtc.toIso8601String(),
        // The day the sentence means is resolved server-side in this zone,
        // never from the phone's idea of the calendar (ADR 0007).
        capturedTimezone: capture.capturedTimezone,
      );
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
