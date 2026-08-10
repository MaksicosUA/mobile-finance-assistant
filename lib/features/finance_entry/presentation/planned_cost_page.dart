import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/planned_cost_controller.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';

/// Records one intended future payment (ADR 0018).
///
/// The screen states plainly that a plan does not move the balance, because a
/// forecast shown next to real money is easy to misread as money that moved.
class PlannedCostPage extends ConsumerStatefulWidget {
  const PlannedCostPage({required this.onSignInRequested, super.key});

  final Future<void> Function() onSignInRequested;

  @override
  ConsumerState<PlannedCostPage> createState() => _PlannedCostPageState();
}

class _PlannedCostPageState extends ConsumerState<PlannedCostPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  bool _signInRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(plannedCostControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(plannedCostControllerProvider);

    if (state is PlannedCostAuthenticationRequired && !_signInRequested) {
      _signInRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await widget.onSignInRequested();
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.plannedCostTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _body(context, l10n, state),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    PlannedCostState state,
  ) {
    return switch (state) {
      PlannedCostLoading() => _centered(
        key: const Key('planned-cost-loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator.adaptive(),
            const SizedBox(height: 16),
            Text(l10n.plannedCostLoading, textAlign: TextAlign.center),
          ],
        ),
      ),
      PlannedCostUnavailable() => _centered(
        key: const Key('planned-cost-unavailable'),
        child: Text(
          l10n.plannedCostAccountRequired,
          textAlign: TextAlign.center,
        ),
      ),
      PlannedCostAuthenticationRequired() => _centered(
        key: const Key('planned-cost-authentication'),
        child: const CircularProgressIndicator.adaptive(),
      ),
      PlannedCostFailure() => _centered(
        key: const Key('planned-cost-failure'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.plannedCostGenericFailure, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  ref.read(plannedCostControllerProvider.notifier).load(),
              child: Text(l10n.plannedCostRetryAction),
            ),
          ],
        ),
      ),
      PlannedCostAccepted(:final plannedCost, :final homeStatus) => _accepted(
        context,
        l10n,
        plannedCost,
        homeStatus,
      ),
      PlannedCostEditing() => _editing(context, l10n, state),
    };
  }

  Widget _centered({required Widget child, Key? key}) {
    return Center(
      key: key,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: child,
      ),
    );
  }

  Widget _editing(
    BuildContext context,
    AppLocalizations l10n,
    PlannedCostEditing state,
  ) {
    final materialL10n = MaterialLocalizations.of(context);
    final message = _failureMessage(l10n, state);
    return ListView(
      key: const Key('planned-cost-editing'),
      padding: const EdgeInsets.symmetric(vertical: 24),
      children: [
        Text(l10n.plannedCostDescription),
        const SizedBox(height: 24),
        TextField(
          key: const Key('planned-cost-title'),
          controller: _title,
          maxLength: 100,
          enabled: !state.isSubmitting,
          decoration: InputDecoration(
            labelText: l10n.plannedCostTitleLabel,
            hintText: l10n.plannedCostTitleHint,
          ),
          onChanged: ref.read(plannedCostControllerProvider.notifier).setTitle,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('planned-cost-amount'),
          controller: _amount,
          enabled: !state.isSubmitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.plannedCostAmountLabel,
            suffixText: state.account.currency,
          ),
          onChanged: ref.read(plannedCostControllerProvider.notifier).setAmount,
        ),
        const SizedBox(height: 24),
        Text(l10n.plannedCostDateLabel),
        const SizedBox(height: 8),
        // Wrap, not Row: at 200% text scale the date and the button do not fit
        // on one 360 dp line, and clipping a control is not an option.
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              materialL10n.formatMediumDate(state.selectedDate),
              key: const Key('planned-cost-date'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            OutlinedButton(
              key: const Key('planned-cost-choose-date'),
              onPressed: state.isSubmitting
                  ? null
                  : () => _pickDate(context, state),
              child: Text(l10n.plannedCostChooseDateAction),
            ),
          ],
        ),
        if (message != null) ...[
          const SizedBox(height: 24),
          _Message(key: const Key('planned-cost-message'), text: message),
        ],
        const SizedBox(height: 32),
        Text(
          l10n.plannedCostListTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (state.plans.isNotEmpty) ...[
          Text(
            l10n.plannedCostConfirmHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        if (state.plans.isEmpty)
          Text(
            l10n.plannedCostListEmpty,
            key: const Key('planned-cost-list-empty'),
          )
        else
          ...state.plans.map(
            (plan) => _PlanRow(
              key: Key('planned-cost-plan-${plan.plannedCostId}'),
              plan: plan,
              isSettling: state.settlingId == plan.plannedCostId,
              onCancel: state.settlingId != null || state.isSubmitting
                  ? null
                  : () => ref
                        .read(plannedCostControllerProvider.notifier)
                        .cancelPlan(plan.plannedCostId),
              onConfirm: state.settlingId != null || state.isSubmitting
                  ? null
                  : () => ref
                        .read(plannedCostControllerProvider.notifier)
                        .confirmPlan(plan),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('planned-cost-submit'),
          onPressed: state.isSubmitting
              ? null
              : () => ref.read(plannedCostControllerProvider.notifier).submit(),
          child: Text(l10n.plannedCostSubmitAction),
        ),
      ],
    );
  }

  Widget _accepted(
    BuildContext context,
    AppLocalizations l10n,
    PlannedCost plannedCost,
    PlannedCostHomeStatus homeStatus,
  ) {
    final materialL10n = MaterialLocalizations.of(context);
    final date = DateTime.tryParse(plannedCost.plannedOn);
    return ListView(
      key: const Key('planned-cost-accepted'),
      padding: const EdgeInsets.symmetric(vertical: 24),
      children: [
        Text(
          l10n.plannedCostAcceptedTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(l10n.plannedCostAcceptedDescription),
        const SizedBox(height: 16),
        Text(plannedCost.title),
        if (date != null) Text(materialL10n.formatMediumDate(date)),
        const SizedBox(height: 16),
        Text(key: const Key('planned-cost-home-status'), switch (homeStatus) {
          PlannedCostHomeStatus.pending => l10n.plannedCostHomePending,
          PlannedCostHomeStatus.updated => l10n.plannedCostHomeUpdated,
          PlannedCostHomeStatus.projectionDelayed =>
            l10n.plannedCostHomeDelayed,
          PlannedCostHomeStatus.authenticationRequired ||
          PlannedCostHomeStatus.failed => l10n.plannedCostHomeFailed,
        }),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('planned-cost-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.plannedCostDoneAction),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, PlannedCostEditing state) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: state.selectedDate,
      firstDate: state.earliestDate,
      lastDate: state.latestDate,
    );
    if (selected == null || !mounted) return;
    ref.read(plannedCostControllerProvider.notifier).selectDate(selected);
  }

  String? _failureMessage(AppLocalizations l10n, PlannedCostEditing state) {
    for (final issue in state.issues) {
      switch (issue.code) {
        case PlannedCostIssueCode.accountUnavailable:
          return l10n.plannedCostIssueAccountUnavailable;
        case PlannedCostIssueCode.accountCurrencyMismatch:
          return l10n.plannedCostIssueCurrencyMismatch;
        case PlannedCostIssueCode.unsupportedCurrency:
          return l10n.plannedCostIssueUnsupportedCurrency;
        case PlannedCostIssueCode.planBeforeAccountBaseline:
          return l10n.plannedCostIssueBeforeBaseline;
        case PlannedCostIssueCode.invalidLifecycleTransition:
        case PlannedCostIssueCode.confirmingOperationMissing:
          return l10n.plannedCostGenericFailure;
      }
    }
    final failure = state.failure;
    if (failure == null) return null;
    return failure.kind == FinanceEntryFailureKind.invalidInput
        ? l10n.plannedCostInvalidInput
        : l10n.plannedCostGenericFailure;
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.plan,
    required this.isSettling,
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  final PlannedCost plan;
  final bool isSettling;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final due = DateTime.tryParse(plan.plannedOn);
    final scheme = Theme.of(context).colorScheme;
    // Overdue is stated in words as well as colour: an obligation must never
    // be signalled by colour alone.
    final dueLabel = plan.isDue
        ? l10n.plannedCostOverdueLabel
        : l10n.plannedCostDueLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.title),
                Text(
                  due == null
                      ? dueLabel
                      : '$dueLabel: ${materialL10n.formatMediumDate(due)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: plan.isDue ? scheme.error : null,
                  ),
                ),
              ],
            ),
          ),
          Text('${plan.amount} ${plan.currency}'),
          if (isSettling)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            )
          else ...[
            Semantics(
              button: true,
              label: l10n.plannedCostConfirmSemantics,
              child: FilledButton.tonal(
                key: Key('planned-cost-confirm-${plan.plannedCostId}'),
                onPressed: onConfirm,
                child: Text(l10n.plannedCostConfirmAction),
              ),
            ),
            Semantics(
              button: true,
              label: l10n.plannedCostCancelSemantics,
              child: TextButton(
                key: Key('planned-cost-cancel-${plan.plannedCostId}'),
                onPressed: onCancel,
                child: Text(l10n.plannedCostCancelAction),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      // Never colour alone: the icon and the text carry the same meaning.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
