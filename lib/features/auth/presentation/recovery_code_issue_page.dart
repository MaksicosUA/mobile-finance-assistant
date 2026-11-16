import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/auth_controller.dart';
import '../application/credentials_controller.dart';

/// Asking for a new recovery code from Profile (ADR 0035).
///
/// Says first what the code is for and that asking replaces the old one, then
/// asks for the password: the code is as good as the password, so an unlocked
/// phone alone must not be enough to mint one.
class RecoveryCodeIssuePage extends ConsumerStatefulWidget {
  const RecoveryCodeIssuePage({super.key});

  @override
  ConsumerState<RecoveryCodeIssuePage> createState() =>
      _RecoveryCodeIssuePageState();
}

class _RecoveryCodeIssuePageState extends ConsumerState<RecoveryCodeIssuePage> {
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
    final state = ref.watch(recoveryCodeIssueControllerProvider);
    final submitting = state is CredentialFormSubmitting;
    final issue = state is CredentialFormReady ? state.issue : null;

    ref.listen<CredentialFormState>(recoveryCodeIssueControllerProvider, (
      previous,
      next,
    ) {
      if (next is! CredentialFormReady) return;
      final message = credentialIssueMessage(l10n, next.issue);
      if (message == null) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    });

    final canSubmit = !submitting && _password.text.isNotEmpty;

    // Leaving mid-request would drop the answer, and the answer is the only
    // place the new code exists.
    return PopScope(
      canPop: !submitting,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.recoveryCodeTitle)),
        body: SafeArea(
          child: ListView(
            key: const Key('recovery-code-issue-page'),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                l10n.recoveryCodeIssueHeadline,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              _Point(
                icon: Icons.key_outlined,
                text: l10n.recoveryCodeIssueWhat,
              ),
              _Point(
                icon: Icons.autorenew_rounded,
                text: l10n.recoveryCodeIssueReplaces,
              ),
              _Point(
                icon: Icons.edit_note_rounded,
                text: l10n.recoveryCodeIssueShownOnce,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('recovery-code-issue-password'),
                controller: _password,
                enabled: !submitting,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                maxLength: 128,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: canSubmit ? (_) => _submit() : null,
                decoration: InputDecoration(
                  labelText: l10n.currentPasswordField,
                  helperText: l10n.recoveryCodeIssuePasswordHelp,
                  helperMaxLines: 2,
                  counterText: '',
                  errorText: issue == CredentialIssue.passwordRejected
                      ? l10n.credentialPasswordRejected
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                key: const Key('recovery-code-issue-submit'),
                onPressed: canSubmit ? _submit : null,
                icon: submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.key_outlined),
                label: Text(l10n.recoveryCodeIssueSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    // Taken before waiting: what follows must happen even if this screen is
    // gone by the time the server answers.
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    final code = await ref
        .read(recoveryCodeIssueControllerProvider.notifier)
        .submit(_password.text);
    if (code == null) return;
    container.read(pendingRecoveryCodeProvider.notifier).show(code);
    container.invalidate(recoveryCodeStatusProvider);
    // Every pushed screen goes, so the code is what the person sees rather
    // than a page left on top of it.
    navigator.popUntil((route) => route.isFirst);
  }
}

/// What to say in passing about a refusal that is not shown beside a field.
String? credentialIssueMessage(AppLocalizations l10n, CredentialIssue? issue) {
  return switch (issue) {
    CredentialIssue.unreachable => l10n.credentialUnreachable,
    CredentialIssue.unavailable => l10n.credentialUnavailable,
    CredentialIssue.authenticationRequired => l10n.credentialAuthentication,
    CredentialIssue.throttled => l10n.authThrottledError,
    // Shown beside the field they are about.
    CredentialIssue.passwordRejected ||
    CredentialIssue.newPasswordRejected ||
    null => null,
  };
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
