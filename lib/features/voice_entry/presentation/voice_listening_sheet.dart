import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/voice_entry_controller.dart';

/// Opens the listening screen above whatever is on screen.
///
/// It closes itself when listening stops, however it stops. Back and a tap
/// outside are taken as Cancel, never silently ignored: a microphone the
/// person thinks they have closed must not go on listening.
Future<void> showVoiceListeningSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    useSafeArea: true,
    builder: (_) => const VoiceListeningSheet(),
  );
}

/// Brings up the listening screen once the microphone is the app's and listening
/// has begun (ADR 0031 amendment).
///
/// Nothing shows while Android asks for the permission, or when the voice input
/// screen is used instead: that one draws itself.
class VoiceListeningHost extends ConsumerWidget {
  const VoiceListeningHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(voiceHeardSoFarProvider, (previous, next) {
      if (previous == null && next != null) {
        unawaited(showVoiceListeningSheet(context));
      }
    });
    return child;
  }
}

/// What the app hears while it listens through pauses (ADR 0031 amendment).
///
/// The words appear as they are recognised, so a misheard number is seen
/// before Done rather than after. Nothing here is stored: the text lives in
/// memory until Done hands it to the sentence field.
class VoiceListeningSheet extends ConsumerStatefulWidget {
  const VoiceListeningSheet({super.key});

  @override
  ConsumerState<VoiceListeningSheet> createState() =>
      _VoiceListeningSheetState();
}

class _VoiceListeningSheetState extends ConsumerState<VoiceListeningSheet> {
  bool _finishing = false;
  bool _closed = false;

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final heard = ref.watch(voiceHeardSoFarProvider);
    ref.listen<String?>(voiceHeardSoFarProvider, (previous, next) {
      if (next == null) _close();
    });
    final controller = ref.read(voiceEntryControllerProvider.notifier);
    final text = heard ?? '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back means "never mind", and the sheet goes once listening has.
        unawaited(controller.cancel());
      },
      // Scrolls rather than overflows: at 200% text the words heard and both
      // buttons do not fit a small phone.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: Column(
            key: const Key('voice-listening-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.mic_rounded,
                    color: theme.colorScheme.primary,
                    semanticLabel: l10n.voiceListeningTitle,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.voiceListeningTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(l10n.voiceListeningHint),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 96),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    // Read out as it changes, so a screen reader follows along.
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        text.isEmpty ? l10n.voiceListeningNothingYet : text,
                        key: const Key('voice-listening-text'),
                        style: text.isEmpty
                            ? theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              )
                            : theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.voiceListeningSilence,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const Key('voice-listening-done'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: _finishing
                    ? null
                    : () {
                        setState(() => _finishing = true);
                        unawaited(controller.finish());
                      },
                icon: _finishing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(l10n.voiceListeningDone),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                key: const Key('voice-listening-cancel'),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => unawaited(controller.cancel()),
                child: Text(l10n.voiceListeningCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
