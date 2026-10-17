import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/auth_controller.dart';
import '../data/auth_api.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({
    super.key,
    required this.mode,
    this.isSubmitting = false,
    this.notice = AuthNotice.none,
    this.issue,
    this.deletionDueAt,
  });

  final AuthMode mode;
  final bool isSubmitting;
  final AuthNotice notice;
  final AuthFailureKind? issue;

  /// When a requested erasure will happen, shown so the person knows how long
  /// they have to change their mind (ADR 0030).
  final DateTime? deletionDueAt;

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _validateContinuously = false;

  @override
  void didUpdateWidget(AuthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _displayNameController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _formKey.currentState?.reset();
      _obscurePassword = true;
      _obscureConfirmation = true;
      _validateContinuously = false;
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isRegister = widget.mode == AuthMode.register;
    final message = widget.issue == null
        ? _noticeMessage(l10n, widget.notice)
        : _issueMessage(l10n, widget.issue!);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            key: const Key('auth-page'),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _validateContinuously
                          ? AutovalidateMode.onUserInteraction
                          : AutovalidateMode.disabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 52,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            isRegister ? l10n.registerTitle : l10n.loginTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            isRegister
                                ? l10n.registerDescription
                                : l10n.loginDescription,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: context.appColors.textSecondary,
                                ),
                          ),
                          if (message != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Semantics(
                              key: const Key('auth-message'),
                              container: true,
                              liveRegion: true,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: context.appColors.surfaceSecondary,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.small,
                                  ),
                                  border: Border.all(
                                    color: context.appColors.border,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  child: Text(message),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          if (isRegister) ...[
                            TextFormField(
                              key: const Key('auth-display-name'),
                              controller: _displayNameController,
                              enabled: !widget.isSubmitting,
                              autofillHints: const [AutofillHints.name],
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              maxLength: 100,
                              decoration: InputDecoration(
                                labelText: l10n.displayNameField,
                                counterText: '',
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? l10n.displayNameRequired
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          TextFormField(
                            key: const Key('auth-email'),
                            controller: _emailController,
                            enabled: !widget.isSubmitting,
                            autofillHints: const [AutofillHints.email],
                            keyboardType: TextInputType.emailAddress,
                            textCapitalization: TextCapitalization.none,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            maxLength: 254,
                            decoration: InputDecoration(
                              labelText: l10n.emailField,
                              counterText: '',
                            ),
                            validator: (value) => _validateEmail(l10n, value),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextFormField(
                            key: const Key('auth-password'),
                            controller: _passwordController,
                            enabled: !widget.isSubmitting,
                            autofillHints: [
                              isRegister
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            obscureText: _obscurePassword,
                            enableSuggestions: false,
                            autocorrect: false,
                            textInputAction: isRegister
                                ? TextInputAction.next
                                : TextInputAction.done,
                            onFieldSubmitted: isRegister || widget.isSubmitting
                                ? null
                                : (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: l10n.passwordField,
                              helperText: isRegister
                                  ? l10n.passwordRequirements
                                  : null,
                              suffixIcon: IconButton(
                                onPressed: widget.isSubmitting
                                    ? null
                                    : () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                tooltip: _obscurePassword
                                    ? l10n.showPassword
                                    : l10n.hidePassword,
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) =>
                                _validatePassword(l10n, value),
                          ),
                          if (isRegister) ...[
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              key: const Key('auth-confirm-password'),
                              controller: _confirmPasswordController,
                              enabled: !widget.isSubmitting,
                              autofillHints: const [AutofillHints.newPassword],
                              obscureText: _obscureConfirmation,
                              enableSuggestions: false,
                              autocorrect: false,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: widget.isSubmitting
                                  ? null
                                  : (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: l10n.confirmPasswordField,
                                suffixIcon: IconButton(
                                  onPressed: widget.isSubmitting
                                      ? null
                                      : () => setState(
                                          () => _obscureConfirmation =
                                              !_obscureConfirmation,
                                        ),
                                  tooltip: _obscureConfirmation
                                      ? l10n.showPassword
                                      : l10n.hidePassword,
                                  icon: Icon(
                                    _obscureConfirmation
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  value != _passwordController.text
                                  ? l10n.passwordsDoNotMatch
                                  : null,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton(
                            key: const Key('auth-submit'),
                            onPressed: widget.isSubmitting ? null : _submit,
                            child: widget.isSubmitting
                                ? SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                    ),
                                  )
                                : Text(
                                    isRegister
                                        ? l10n.registerAction
                                        : l10n.loginAction,
                                  ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextButton(
                            key: const Key('auth-switch-mode'),
                            onPressed: widget.isSubmitting
                                ? null
                                : () => ref
                                      .read(authControllerProvider.notifier)
                                      .showMode(
                                        isRegister
                                            ? AuthMode.login
                                            : AuthMode.register,
                                      ),
                            child: Text(
                              isRegister
                                  ? l10n.haveAccountAction
                                  : l10n.createAccountAction,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _validateContinuously = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = ref.read(authControllerProvider.notifier);
    if (widget.mode == AuthMode.register) {
      await controller.register(
        displayName: _displayNameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
    } else {
      await controller.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
    }
  }

  String? _validateEmail(AppLocalizations l10n, String? value) {
    final candidate = value?.trim() ?? '';
    final separator = candidate.indexOf('@');
    if (separator < 1 ||
        separator != candidate.lastIndexOf('@') ||
        separator == candidate.length - 1 ||
        !candidate.substring(separator + 1).contains('.')) {
      return l10n.emailInvalid;
    }
    return null;
  }

  String? _validatePassword(AppLocalizations l10n, String? value) {
    final candidate = value ?? '';
    if (candidate.runes.length < 12 ||
        candidate.runes.length > 128 ||
        utf8.encode(candidate).length > 1024) {
      return l10n.passwordInvalid;
    }
    return null;
  }

  String? _noticeMessage(AppLocalizations l10n, AuthNotice notice) {
    return switch (notice) {
      AuthNotice.none => null,
      AuthNotice.sessionExpired => l10n.authSessionExpiredNotice,
      AuthNotice.signedOut => l10n.signedOutNotice,
      AuthNotice.deletionScheduled => switch (widget.deletionDueAt) {
        final due? => l10n.accountDeletionScheduledNotice(due.toLocal()),
        null => l10n.accountDeletionScheduledNoticeUndated,
      },
      // Said on arrival instead, once the person is signed in.
      AuthNotice.deletionCancelled => null,
    };
  }

  String _issueMessage(AppLocalizations l10n, AuthFailureKind issue) {
    return switch (issue) {
      AuthFailureKind.invalidCredentials => l10n.invalidCredentialsError,
      AuthFailureKind.emailInUse => l10n.emailInUseError,
      AuthFailureKind.invalidInput => l10n.authInvalidInputError,
      AuthFailureKind.invalidRefresh => l10n.authSessionExpiredNotice,
      AuthFailureKind.throttled => l10n.authThrottledError,
      AuthFailureKind.offline => l10n.authOfflineError,
      AuthFailureKind.timeout => l10n.authTimeoutError,
      AuthFailureKind.serviceUnavailable => l10n.authServiceError,
      AuthFailureKind.malformedResponse ||
      AuthFailureKind.unknown => l10n.authUnexpectedError,
      AuthFailureKind.localStorage => l10n.authSecureStorageError,
    };
  }
}
