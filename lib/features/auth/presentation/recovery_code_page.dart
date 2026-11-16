import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/auth_controller.dart';
import '../domain/recovery_code.dart';

/// Puts a waiting recovery code above [child] until the person has kept it.
///
/// The same tree whether or not a code is waiting, so what is underneath keeps
/// its state and is simply out of reach meanwhile: not drawn, not focusable,
/// not read out. It covers a signed-out page as readily as the app, because a
/// reset hands over the next code even when the sign-in after it failed.
class RecoveryCodeCover extends ConsumerWidget {
  const RecoveryCodeCover({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(pendingRecoveryCodeProvider);
    final covered = code != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: covered,
          child: TickerMode(
            enabled: !covered,
            child: ExcludeFocus(excluding: covered, child: child),
          ),
        ),
        if (code != null)
          RecoveryCodePage(
            code: code,
            onKept: () =>
                ref.read(pendingRecoveryCodeProvider.notifier).acknowledge(),
          ),
      ],
    );
  }
}

/// The one time a recovery code is on screen (ADR 0035).
///
/// It cannot be left by going back, and it cannot be finished without saying
/// the code has been kept: after this the phone forgets it and the server never
/// knew it. Shown above everything else by the auth gate, which also keeps the
/// screen out of screenshots and the app switcher while it is up.
class RecoveryCodePage extends StatefulWidget {
  const RecoveryCodePage({required this.code, required this.onKept, super.key});

  final RecoveryCode code;

  /// The person says they have kept the code.
  final VoidCallback onKept;

  @override
  State<RecoveryCodePage> createState() => _RecoveryCodePageState();
}

class _RecoveryCodePageState extends State<RecoveryCodePage> {
  bool _kept = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.recoveryCodeTitle),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              // Built whole rather than lazily: it is one short page, and the
              // button that ends it must exist for a screen reader to reach.
              child: SingleChildScrollView(
                key: const Key('recovery-code-page'),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.recoveryCodeHeadline,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(l10n.recoveryCodeIntro),
                    const SizedBox(height: AppSpacing.md),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.appColors.surfaceSecondary,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                        border: Border.all(color: context.appColors.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        // Selectable, and scaled down rather than wrapped: a
                        // code broken across two lines is copied down wrongly.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SelectableText(
                            widget.code.value,
                            key: const Key('recovery-code-value'),
                            maxLines: 1,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      key: const Key('recovery-code-copy'),
                      onPressed: () => _copy(l10n),
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(l10n.recoveryCodeCopyAction),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Point(
                      icon: Icons.edit_note_rounded,
                      text: l10n.recoveryCodeKeepPaper,
                    ),
                    _Point(
                      icon: Icons.phonelink_erase_rounded,
                      text: l10n.recoveryCodeKeepElsewhere,
                    ),
                    _Point(
                      icon: Icons.visibility_off_outlined,
                      text: l10n.recoveryCodeKeepSecret,
                    ),
                    _Point(
                      icon: Icons.autorenew_rounded,
                      text: l10n.recoveryCodeSingleUse,
                    ),
                    _Point(
                      icon: Icons.no_photography_outlined,
                      text: l10n.recoveryCodeNoScreenshot,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    CheckboxListTile(
                      key: const Key('recovery-code-kept'),
                      value: _kept,
                      onChanged: (value) =>
                          setState(() => _kept = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.recoveryCodeSavedCheck),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton(
                      key: const Key('recovery-code-done'),
                      onPressed: _kept ? widget.onKept : null,
                      child: Text(l10n.recoveryCodeDoneAction),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copy(AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: widget.code.value));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(l10n.recoveryCodeCopied)));
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
