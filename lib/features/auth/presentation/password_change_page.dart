import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/credentials_controller.dart';
import '../domain/password_rules.dart';
import 'recovery_code_issue_page.dart';

/// Changing the password while signed in (ADR 0035).
class PasswordChangePage extends ConsumerStatefulWidget {
  const PasswordChangePage({super.key});

  @override
  ConsumerState<PasswordChangePage> createState() => _PasswordChangePageState();
}

class _PasswordChangePageState extends ConsumerState<PasswordChangePage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _replacement = TextEditingController();
  final _confirmation = TextEditingController();

  bool _validateContinuously = false;

  @override
  void dispose() {
    _current.dispose();
    _replacement.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(passwordChangeControllerProvider);
    final submitting = state is CredentialFormSubmitting;
    final issue = state is CredentialFormReady ? state.issue : null;

    ref.listen<CredentialFormState>(passwordChangeControllerProvider, (
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

    // Leaving mid-request would leave the person not knowing which password
    // their account has.
    return PopScope(
      canPop: !submitting,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.passwordChangeTitle)),
        body: SafeArea(
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              autovalidateMode: _validateContinuously
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: ListView(
                key: const Key('password-change-page'),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Text(l10n.passwordChangeIntro),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const Key('password-change-current'),
                    controller: _current,
                    enabled: !submitting,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: 128,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.currentPasswordField,
                      counterText: '',
                      errorText: issue == CredentialIssue.passwordRejected
                          ? l10n.credentialPasswordRejected
                          : null,
                    ),
                    validator: (value) => (value ?? '').isEmpty
                        ? l10n.credentialPasswordRejected
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const Key('password-change-new'),
                    controller: _replacement,
                    enabled: !submitting,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: 128,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.newPasswordField,
                      helperText: l10n.passwordRequirements,
                      counterText: '',
                      errorText: issue == CredentialIssue.newPasswordRejected
                          ? l10n.passwordInvalid
                          : null,
                    ),
                    validator: (value) => isAcceptablePassword(value ?? '')
                        ? null
                        : l10n.passwordInvalid,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const Key('password-change-confirm'),
                    controller: _confirmation,
                    enabled: !submitting,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: 128,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: submitting ? null : (_) => _submit(l10n),
                    decoration: InputDecoration(
                      labelText: l10n.confirmPasswordField,
                      counterText: '',
                    ),
                    validator: (value) => value != _replacement.text
                        ? l10n.passwordsDoNotMatch
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    key: const Key('password-change-submit'),
                    onPressed: submitting ? null : () => _submit(l10n),
                    child: submitting
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(l10n.recoverAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(AppLocalizations l10n) async {
    setState(() => _validateContinuously = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final changed = await ref
        .read(passwordChangeControllerProvider.notifier)
        .submit(currentPassword: _current.text, newPassword: _replacement.text);
    if (!changed) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(l10n.passwordChangeDone)));
    if (mounted) navigator.pop();
  }
}
