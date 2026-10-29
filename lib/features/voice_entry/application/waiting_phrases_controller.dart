import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../../core/platform/finance_capture_context.dart';
import '../../auth/application/auth_controller.dart';
import '../../finance_entry/data/finance_command_id.dart';
import '../data/waiting_phrase_store.dart';
import '../domain/waiting_phrase.dart';

/// The account the phrases belong to: the signed-in session's scope, or null
/// when nobody is signed in — always, in the fixture build, which has no
/// session. Replaceable so a test needs no secure storage.
final waitingPhraseScopeProvider = Provider<Future<String?> Function()>(
  (ref) => isNetworkBackendConfigured
      ? () async => (await ref.read(authSessionStoreProvider).readAuthSession())
            ?.cacheScopeId
      : () async => null,
);

final waitingPhraseClockProvider = Provider<DateTime Function()>(
  (_) =>
      () => DateTime.now().toUtc(),
);

/// Phrases said on Home that the server has not read yet, oldest first
/// (ADR 0032).
final waitingPhrasesProvider =
    NotifierProvider<WaitingPhrases, List<WaitingPhrase>>(WaitingPhrases.new);

/// Keeps a heard phrase until the server has read it, then lets it go.
///
/// Nothing here parses or records: a waiting phrase becomes the ordinary card,
/// and the ordinary confirmation is what writes. Every failure degrades to
/// "nothing kept" — speaking must never be refused because storage was not
/// available.
class WaitingPhrases extends Notifier<List<WaitingPhrase>> {
  int _generation = 0;

  WaitingPhraseStore get _store => ref.read(waitingPhraseStoreProvider);

  DateTime _now() => ref.read(waitingPhraseClockProvider)();

  @override
  List<WaitingPhrase> build() {
    ref.watch(authAccountEpochProvider);
    final generation = ++_generation;
    Future.microtask(() => _reload(generation));
    return const [];
  }

  /// Reads the list again, dropping whatever has outlived its 30 days.
  Future<void> refresh() => _reload(++_generation);

  /// Keeps [text], said at [capture]. Null when it could not be kept: nobody is
  /// signed in, [maximumWaitingPhrases] are already waiting, or storage failed.
  Future<WaitingPhrase?> keep({
    required String text,
    required FinanceCaptureContext capture,
  }) async {
    if (!WaitingPhrase.isReadableSentence(text)) return null;
    try {
      final scope = await ref.read(waitingPhraseScopeProvider)();
      if (scope == null || !ref.mounted) return null;
      final phrase = WaitingPhrase(
        id: newFinanceCommandId(),
        text: text,
        saidAt: capture.capturedAtUtc,
        saidInTimezone: capture.capturedTimezone,
      );
      final waiting = await _store.add(
        scopeId: scope,
        phrase: phrase,
        now: _now(),
      );
      if (waiting == null) return null;
      _publish(waiting);
      return phrase;
    } on Object {
      return null;
    }
  }

  /// Lets [id] go: the server has read it, or the person deleted it.
  Future<void> forget(String id) async {
    try {
      final scope = await ref.read(waitingPhraseScopeProvider)();
      if (scope == null || !ref.mounted) return;
      _publish(await _store.remove(scopeId: scope, id: id, now: _now()));
    } on Object {
      // Left waiting: the next reading of the same words forgets it again,
      // and thirty days ends it regardless.
    }
  }

  Future<void> _reload(int generation) async {
    try {
      final scope = await ref.read(waitingPhraseScopeProvider)();
      final waiting = scope == null
          ? const <WaitingPhrase>[]
          : await _store.read(scopeId: scope, now: _now());
      if (ref.mounted && generation == _generation) state = waiting;
    } on Object {
      // Nothing to show is the honest answer when storage cannot be read.
    }
  }

  void _publish(List<WaitingPhrase> waiting) {
    _generation += 1;
    if (ref.mounted) state = waiting;
  }
}
