import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/account_deletion_controller.dart';
import '../application/account_export_controller.dart';

/// Asking for one's own account to be erased (ADR 0030).
///
/// Says the uncomfortable parts before anything is asked: what goes, when,
/// how to undo it, and that backups keep it a little longer. Offers the export
/// first, because after the week there is nothing left to export.
class AccountDeletionPage extends ConsumerStatefulWidget {
  const AccountDeletionPage({super.key});

  @override
  ConsumerState<AccountDeletionPage> createState() =>
      _AccountDeletionPageState();
}

class _AccountDeletionPageState extends ConsumerState<AccountDeletionPage> {
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(accountDeletionControllerProvider);
    final unsent = ref.watch(unsentOperationCountProvider);
    final exporting =
        ref.watch(accountExportControllerProvider) is AccountExportPreparing;
    final submitting = state is AccountDeletionSubmitting;
    final issue = state is AccountDeletionReady ? state.issue : null;

    ref.listen<AccountDeletionState>(accountDeletionControllerProvider, (
      previous,
      next,
    ) {
      if (next is! AccountDeletionReady) return;
      final message = switch (next.issue) {
        AccountDeletionIssue.unreachable => l10n.accountDeletionUnreachable,
        AccountDeletionIssue.unavailable => l10n.accountDeletionUnavailable,
        AccountDeletionIssue.authenticationRequired =>
          l10n.accountDeletionAuthentication,
        // Shown beside the field instead.
        AccountDeletionIssue.passwordRejected || null => null,
      };
      if (message == null) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    });

    final canSubmit = !submitting && _password.text.isNotEmpty;

    // Leaving mid-request would drop the answer, and with it the sign-out the
    // server has already done everywhere else.
    return PopScope(
      canPop: !submitting,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.accountDeletionTitle)),
        body: SafeArea(
          child: ListView(
            key: const Key('account-deletion-page'),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                l10n.accountDeletionHeadline,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              _Point(
                icon: Icons.delete_forever_outlined,
                text: l10n.accountDeletionWhat,
              ),
              _Point(
                icon: Icons.devices_outlined,
                text: l10n.accountDeletionSignedOut,
              ),
              _Point(
                icon: Icons.backup_outlined,
                text: l10n.accountDeletionBackups,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                key: const Key('account-deletion-export-first'),
                onPressed: exporting
                    ? null
                    : () => ref
                          .read(accountExportControllerProvider.notifier)
                          .exportAndShare(),
                icon: const Icon(Icons.file_download_outlined),
                label: Text(
                  exporting
                      ? l10n.accountExportPreparing
                      : l10n.accountDeletionExportFirst,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (unsent > 0) ...[
                Card(
                  key: const Key('account-deletion-unsent'),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(l10n.accountDeletionUnsent(unsent)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextField(
                key: const Key('account-deletion-password'),
                controller: _password,
                enabled: !submitting,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.accountDeletionPasswordLabel,
                  helperText: l10n.accountDeletionPasswordHelp,
                  helperMaxLines: 2,
                  errorText: issue == AccountDeletionIssue.passwordRejected
                      ? l10n.accountDeletionPasswordRejected
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                key: const Key('account-deletion-submit'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: canSubmit ? () => _confirm(l10n) : null,
                icon: submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.accountDeletionSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('account-deletion-confirm'),
        title: Text(l10n.accountDeletionConfirmTitle),
        content: Text(l10n.accountDeletionConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.accountDeletionConfirmCancel),
          ),
          TextButton(
            key: const Key('account-deletion-confirm-accept'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.accountDeletionConfirmAccept),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Taken before waiting: what follows must happen even if this screen is
    // gone by the time the server answers.
    final complete = ref.read(accountDeletionCompletionProvider);
    final navigator = Navigator.of(context);
    final dueAt = await ref
        .read(accountDeletionControllerProvider.notifier)
        .submit(_password.text);
    if (dueAt == null) return;
    // Every pushed screen goes first, so the sign-in page that replaces the
    // app is what the person sees rather than a page left on top of it.
    navigator.popUntil((route) => route.isFirst);
    await complete(dueAt);
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
