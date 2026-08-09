import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/account_baseline_controller.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';

class AccountBaselinePage extends ConsumerStatefulWidget {
  const AccountBaselinePage({super.key, this.onSignInRequested});

  final Future<void> Function()? onSignInRequested;

  @override
  ConsumerState<AccountBaselinePage> createState() =>
      _AccountBaselinePageState();
}

class _AccountBaselinePageState extends ConsumerState<AccountBaselinePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(accountBaselineControllerProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(authAccountEpochProvider, (previous, next) {
      if (previous == null || previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(accountBaselineControllerProvider.notifier).load();
        }
      });
    });
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(accountBaselineControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.screenMaxWidth,
            ),
            child: Column(
              key: const Key('account-baseline-page'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    0,
                  ),
                  child: Row(
                    children: [
                      IconButton.outlined(
                        key: const Key('account-baseline-back'),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: l10n.backLabel,
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n.baselineCorrectionTitle,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: const Key('account-baseline-scroll'),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [_content(context, state)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AccountBaselineState state) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(accountBaselineControllerProvider.notifier);
    return switch (state) {
      AccountBaselineLoading() => _LoadingView(
        label: l10n.baselineCorrectionLoading,
      ),
      AccountBaselineUnavailable(:final reason) => _UnavailableView(
        reason: reason,
        onRetry: controller.load,
      ),
      AccountBaselineEditing() => _EditingView(
        state: state,
        onChooseDate: () => _chooseDate(state),
        onEvaluate: controller.evaluate,
      ),
      AccountBaselineReviewing() => _ReviewView(
        state: state,
        onEdit: controller.edit,
        onConfirm: controller.confirm,
      ),
      AccountBaselineAccepted() => _AcceptedView(
        state: state,
        onDone: () => Navigator.of(context).pop(),
      ),
      AccountBaselineAuthenticationRequired() => _AuthenticationView(
        onSignInRequested: widget.onSignInRequested,
      ),
      AccountBaselineFailure(:final failure) => _FailureView(
        title: l10n.baselineLoadFailed,
        failure: failure,
        onRetry: controller.load,
      ),
    };
  }

  Future<void> _chooseDate(AccountBaselineEditing state) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showDatePicker(
      context: context,
      initialDate: state.selectedDate,
      firstDate: state.earliestDate,
      lastDate: state.latestDate,
      helpText: l10n.baselineChooseDateAction,
      cancelText: l10n.cancelAction,
      confirmText: l10n.baselineChooseDateAction,
    );
    if (selected != null && mounted) {
      ref.read(accountBaselineControllerProvider.notifier).selectDate(selected);
    }
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _EditingView extends StatelessWidget {
  const _EditingView({
    required this.state,
    required this.onChooseDate,
    required this.onEvaluate,
  });

  final AccountBaselineEditing state;
  final VoidCallback onChooseDate;
  final VoidCallback onEvaluate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentDate = _localizedDate(
      context,
      _parseWireDate(state.account.openingBalanceOn),
    );
    final selectedDate = _localizedDate(context, state.selectedDate);
    return Column(
      key: const Key('account-baseline-editing'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.baselineCorrectionDescription,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        _DateCard(
          rows: [
            (label: l10n.accountLabel, value: state.account.name),
            (label: l10n.baselineCurrentDateLabel, value: currentDate),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (state.issues.isNotEmpty || state.failure != null) ...[
          _InlineIssue(
            message: _baselineMessage(
              l10n,
              issues: state.issues,
              failure: state.failure,
            ),
            requestId: state.failure?.requestId,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Card(
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            button: true,
            enabled: !state.isSubmitting,
            excludeSemantics: true,
            label: '${l10n.baselineNewDateLabel}: $selectedDate',
            onTap: state.isSubmitting ? null : onChooseDate,
            child: InkWell(
              key: const Key('account-baseline-date'),
              onTap: state.isSubmitting ? null : onChooseDate,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.baselineNewDateLabel,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            selectedDate,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    const ExcludeSemantics(
                      child: Icon(Icons.edit_calendar_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.baselineDateRangeHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          key: const Key('account-baseline-evaluate'),
          onPressed: state.isSubmitting ? null : onEvaluate,
          child: _ButtonContent(
            loading: state.isSubmitting,
            label: l10n.continueToReviewAction,
          ),
        ),
      ],
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.state,
    required this.onEdit,
    required this.onConfirm,
  });

  final AccountBaselineReviewing state;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentDate = _localizedDate(
      context,
      _parseWireDate(state.review.currentOpeningBalanceOn),
    );
    final newDate = _localizedDate(
      context,
      _parseWireDate(state.review.draft.openingBalanceOn),
    );
    return Column(
      key: const Key('account-baseline-review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.baselineReviewTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.baselineReviewDescription,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (state.failure case final failure?) ...[
          _InlineIssue(
            message: _failureMessage(l10n, failure),
            requestId: failure.requestId,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _DateCard(
          rows: [
            (label: l10n.accountLabel, value: state.account.name),
            (label: l10n.baselineCurrentDateLabel, value: currentDate),
            (label: l10n.baselineNewDateLabel, value: newDate),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton(
          key: const Key('account-baseline-edit'),
          onPressed: state.isSubmitting ? null : onEdit,
          child: Text(l10n.editAction),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          key: const Key('account-baseline-confirm'),
          onPressed: state.isSubmitting ? null : onConfirm,
          child: _ButtonContent(
            loading: state.isSubmitting,
            label: l10n.baselineConfirmAction,
          ),
        ),
      ],
    );
  }
}

class _AcceptedView extends StatelessWidget {
  const _AcceptedView({required this.state, required this.onDone});

  final AccountBaselineAccepted state;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final newDate = _localizedDate(
      context,
      _parseWireDate(state.commit.account.openingBalanceOn),
    );
    final homeDelayed =
        state.homeStatus != AccountBaselineHomeStatus.pending &&
        state.homeStatus != AccountBaselineHomeStatus.updated;
    return Column(
      key: const Key('account-baseline-accepted'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusPanel(
          icon: Icons.check_circle_outline_rounded,
          title: l10n.baselineSuccessTitle,
          description: homeDelayed
              ? l10n.baselineHomeDelayedDescription
              : l10n.baselineSuccessDescription(newDate),
          progress: state.homeStatus == AccountBaselineHomeStatus.pending,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          key: const Key('account-baseline-done'),
          onPressed: onDone,
          child: Text(l10n.baselineDoneAction),
        ),
      ],
    );
  }
}

class _UnavailableView extends StatelessWidget {
  const _UnavailableView({required this.reason, required this.onRetry});

  final AccountBaselineUnavailableReason reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final description = switch (reason) {
      AccountBaselineUnavailableReason.accountRequired =>
        l10n.baselineAccountRequired,
      AccountBaselineUnavailableReason.minimumDate =>
        l10n.baselineMinimumDateReached,
    };
    return Column(
      key: const Key('account-baseline-unavailable'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusPanel(
          icon: Icons.info_outline_rounded,
          title: l10n.baselineUnavailableTitle,
          description: description,
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton(
          key: const Key('account-baseline-retry'),
          onPressed: onRetry,
          child: Text(l10n.retryAction),
        ),
      ],
    );
  }
}

class _AuthenticationView extends StatelessWidget {
  const _AuthenticationView({required this.onSignInRequested});

  final Future<void> Function()? onSignInRequested;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('account-baseline-auth-required'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusPanel(
          icon: Icons.lock_clock_outlined,
          title: l10n.authExpiredTitle,
          description: l10n.authExpiredDescription,
        ),
        if (onSignInRequested != null) ...[
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const Key('account-baseline-sign-in'),
            onPressed: onSignInRequested,
            child: Text(l10n.signInAgainAction),
          ),
        ],
      ],
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.title,
    required this.failure,
    required this.onRetry,
  });

  final String title;
  final FinanceEntryFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('account-baseline-failure'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusPanel(
          icon: Icons.error_outline_rounded,
          title: title,
          description: _failureMessage(l10n, failure),
          requestId: failure.requestId,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          key: const Key('account-baseline-retry'),
          onPressed: onRetry,
          child: Text(l10n.retryAction),
        ),
      ],
    );
  }
}

class _DateCard extends StatelessWidget {
  const _DateCard({required this.rows});

  final List<({String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            for (var index = 0; index < rows.length; index += 1) ...[
              _DateRow(row: rows[index]),
              if (index != rows.length - 1)
                Divider(height: AppSpacing.lg, color: context.appColors.border),
            ],
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.row});

  final ({String label, String value}) row;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale > 1.5) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Text(row.value, style: Theme.of(context).textTheme.titleMedium),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(row.label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            row.value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _InlineIssue extends StatelessWidget {
  const _InlineIssue({required this.message, this.requestId});

  final String message;
  final String? requestId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.appColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  if (requestId case final value?) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.requestIdLabel(value),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.title,
    required this.description,
    this.requestId,
    this.progress = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? requestId;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(description, textAlign: TextAlign.center),
            if (requestId case final value?) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.requestIdLabel(value),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (progress) ...[
              const SizedBox(height: AppSpacing.md),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({required this.loading, required this.label});

  final bool loading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading) ...[
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
  }
}

String _baselineMessage(
  AppLocalizations l10n, {
  required List<FinanceBaselineIssue> issues,
  required FinanceEntryFailure? failure,
}) {
  final allIssues = issues.isNotEmpty
      ? issues
      : failure?.baselineIssues ?? const <FinanceBaselineIssue>[];
  if (allIssues.any(
    (issue) => issue.code == FinanceBaselineIssueCode.baselineNotEarlier,
  )) {
    return l10n.baselineNotEarlierError;
  }
  if (allIssues.any(
    (issue) => issue.code == FinanceBaselineIssueCode.baselineDateInFuture,
  )) {
    return l10n.baselineFutureError;
  }
  if (allIssues.any(
    (issue) =>
        issue.code == FinanceBaselineIssueCode.baselineAfterExistingOperation,
  )) {
    return l10n.baselineAfterOperationError;
  }
  return failure == null
      ? l10n.financeValidationRejected
      : _failureMessage(l10n, failure);
}

String _failureMessage(AppLocalizations l10n, FinanceEntryFailure failure) {
  if (failure.baselineIssues.isNotEmpty) {
    return _baselineMessage(
      l10n,
      issues: failure.baselineIssues,
      failure: null,
    );
  }
  return switch (failure.kind) {
    FinanceEntryFailureKind.invalidInput => l10n.financeInvalidInput,
    FinanceEntryFailureKind.unauthenticated ||
    FinanceEntryFailureKind.unauthorized => l10n.authExpiredDescription,
    FinanceEntryFailureKind.sessionChanged => l10n.financeSessionChanged,
    FinanceEntryFailureKind.interrupted => l10n.financeServiceError,
    FinanceEntryFailureKind.conflict => l10n.financeConflictError,
    FinanceEntryFailureKind.rejected => l10n.financeValidationRejected,
    FinanceEntryFailureKind.offline => l10n.financeOfflineError,
    FinanceEntryFailureKind.timeout => l10n.financeTimeoutError,
    FinanceEntryFailureKind.serviceUnavailable => l10n.financeServiceError,
    FinanceEntryFailureKind.securityFailure => l10n.financeSecurityError,
    FinanceEntryFailureKind.localStorage => l10n.financeLocalStorageError,
    FinanceEntryFailureKind.malformedResponse ||
    FinanceEntryFailureKind.unknown => l10n.baselineChangeFailed,
  };
}

DateTime _parseWireDate(String value) {
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null ||
      '${parsed.year.toString().padLeft(4, '0')}-'
              '${parsed.month.toString().padLeft(2, '0')}-'
              '${parsed.day.toString().padLeft(2, '0')}' !=
          value) {
    throw const FormatException('Invalid calendar date.');
  }
  return parsed;
}

String _localizedDate(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatMediumDate(value);
