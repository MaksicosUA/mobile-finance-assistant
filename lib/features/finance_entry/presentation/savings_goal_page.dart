import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/savings_goal_controller.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';

/// Savings goals and the contributions that fill them (ADR 0019).
///
/// The screen states plainly that setting money aside does not change the
/// balance, because an earmark shown next to real money is easy to misread as
/// money that moved.
class SavingsGoalPage extends ConsumerStatefulWidget {
  const SavingsGoalPage({required this.onSignInRequested, super.key});

  final Future<void> Function() onSignInRequested;

  @override
  ConsumerState<SavingsGoalPage> createState() => _SavingsGoalPageState();
}

class _SavingsGoalPageState extends ConsumerState<SavingsGoalPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _target = TextEditingController();
  final TextEditingController _monthly = TextEditingController();
  final TextEditingController _contribution = TextEditingController();
  bool _signInRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(savingsGoalControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _monthly.dispose();
    _contribution.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(savingsGoalControllerProvider);

    if (state is SavingsGoalAuthenticationRequired && !_signInRequested) {
      _signInRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await widget.onSignInRequested();
      });
    }

    // The controller clears the typed amount once an entry is accepted, so the
    // field must follow it rather than keep a number that was already used.
    if (state is SavingsGoalReady && state.contributionAmount.isEmpty) {
      _contribution.clear();
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.savingsGoalTitle)),
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
    SavingsGoalScreenState state,
  ) {
    return switch (state) {
      SavingsGoalLoading() => _centered(
        key: const Key('savings-goal-loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator.adaptive(),
            const SizedBox(height: 16),
            Text(l10n.savingsGoalLoading, textAlign: TextAlign.center),
          ],
        ),
      ),
      SavingsGoalUnavailable() => _centered(
        key: const Key('savings-goal-unavailable'),
        child: Text(
          l10n.savingsGoalAccountRequired,
          textAlign: TextAlign.center,
        ),
      ),
      SavingsGoalAuthenticationRequired() => _centered(
        key: const Key('savings-goal-authentication'),
        child: const CircularProgressIndicator.adaptive(),
      ),
      SavingsGoalFailure() => _centered(
        key: const Key('savings-goal-failure'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.savingsGoalGenericFailure, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  ref.read(savingsGoalControllerProvider.notifier).load(),
              child: Text(l10n.savingsGoalRetryAction),
            ),
          ],
        ),
      ),
      SavingsGoalReady() => _ready(context, l10n, state),
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

  Widget _ready(
    BuildContext context,
    AppLocalizations l10n,
    SavingsGoalReady state,
  ) {
    final controller = ref.read(savingsGoalControllerProvider.notifier);
    final message = _failureMessage(l10n, state);
    final busy = state.isSubmitting || state.busyGoalId != null;
    return ListView(
      key: const Key('savings-goal-ready'),
      padding: const EdgeInsets.symmetric(vertical: 24),
      children: [
        Text(l10n.savingsGoalDescription),
        if (message != null) ...[
          const SizedBox(height: 24),
          _Message(key: const Key('savings-goal-message'), text: message),
        ],
        const SizedBox(height: 24),
        if (state.goals.isEmpty && !state.isCreating)
          Text(l10n.savingsGoalEmpty, key: const Key('savings-goal-list-empty'))
        else
          ...state.goals.map(
            (goal) => _GoalCard(
              key: Key('savings-goal-card-${goal.goalId}'),
              goal: goal,
              isBusy: state.busyGoalId == goal.goalId,
              amountController: _contribution,
              onAmountChanged: controller.setContributionAmount,
              onDeposit: busy
                  ? null
                  : () => controller.recordContribution(
                      goal,
                      GoalContributionDirection.deposit,
                    ),
              onWithdraw: busy
                  ? null
                  : () => controller.recordContribution(
                      goal,
                      GoalContributionDirection.withdrawal,
                    ),
              onCancel: busy ? null : () => controller.cancelGoal(goal.goalId),
            ),
          ),
        const SizedBox(height: 24),
        if (state.isCreating)
          _createForm(context, l10n, state)
        else
          FilledButton(
            key: const Key('savings-goal-start-create'),
            onPressed: busy ? null : controller.startCreating,
            child: Text(l10n.savingsGoalCreateAction),
          ),
      ],
    );
  }

  Widget _createForm(
    BuildContext context,
    AppLocalizations l10n,
    SavingsGoalReady state,
  ) {
    final controller = ref.read(savingsGoalControllerProvider.notifier);
    final materialL10n = MaterialLocalizations.of(context);
    return Column(
      key: const Key('savings-goal-create-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('savings-goal-title'),
          controller: _title,
          maxLength: 100,
          enabled: !state.isSubmitting,
          decoration: InputDecoration(
            labelText: l10n.savingsGoalTitleLabel,
            hintText: l10n.savingsGoalTitleHint,
          ),
          onChanged: controller.setTitle,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('savings-goal-target'),
          controller: _target,
          enabled: !state.isSubmitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.savingsGoalTargetLabel,
            suffixText: state.account.currency,
          ),
          onChanged: controller.setTargetAmount,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('savings-goal-monthly'),
          controller: _monthly,
          enabled: !state.isSubmitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.savingsGoalMonthlyLabel,
            helperText: l10n.savingsGoalMonthlyHelper,
            helperMaxLines: 3,
            suffixText: state.account.currency,
          ),
          onChanged: controller.setMonthlyContribution,
        ),
        const SizedBox(height: 24),
        Text(l10n.savingsGoalDateLabel),
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
              key: const Key('savings-goal-date'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            OutlinedButton(
              key: const Key('savings-goal-choose-date'),
              onPressed: state.isSubmitting
                  ? null
                  : () => _pickDate(context, state),
              child: Text(l10n.savingsGoalChooseDateAction),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('savings-goal-submit'),
              onPressed: state.isSubmitting ? null : controller.submit,
              child: Text(l10n.savingsGoalSubmitAction),
            ),
            TextButton(
              key: const Key('savings-goal-cancel-create'),
              onPressed: state.isSubmitting ? null : controller.cancelCreating,
              child: Text(l10n.savingsGoalCancelCreateAction),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, SavingsGoalReady state) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: state.selectedDate,
      firstDate: state.earliestDate,
      lastDate: state.latestDate,
    );
    if (selected == null || !mounted) return;
    ref.read(savingsGoalControllerProvider.notifier).selectTargetDate(selected);
  }

  String? _failureMessage(AppLocalizations l10n, SavingsGoalReady state) {
    for (final issue in state.issues) {
      switch (issue.code) {
        case SavingsGoalIssueCode.accountUnavailable:
          return l10n.savingsGoalIssueAccountUnavailable;
        case SavingsGoalIssueCode.accountCurrencyMismatch:
          return l10n.savingsGoalIssueCurrencyMismatch;
        case SavingsGoalIssueCode.unsupportedCurrency:
          return l10n.savingsGoalIssueUnsupportedCurrency;
        case SavingsGoalIssueCode.targetBeforeAccountBaseline:
        case SavingsGoalIssueCode.contributionBeforeAccountBaseline:
          return l10n.savingsGoalIssueBeforeBaseline;
        case SavingsGoalIssueCode.futureContributionDate:
          return l10n.savingsGoalIssueFutureContribution;
        case SavingsGoalIssueCode.goalNotActive:
          return l10n.savingsGoalIssueNotActive;
        case SavingsGoalIssueCode.withdrawalExceedsGoalBalance:
          return l10n.savingsGoalIssueWithdrawalTooLarge;
      }
    }
    final failure = state.failure;
    if (failure == null) return null;
    return failure.kind == FinanceEntryFailureKind.invalidInput
        ? l10n.savingsGoalInvalidInput
        : l10n.savingsGoalGenericFailure;
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.isBusy,
    required this.amountController,
    required this.onAmountChanged,
    required this.onDeposit,
    required this.onWithdraw,
    required this.onCancel,
    super.key,
  });

  final SavingsGoal goal;
  final bool isBusy;
  final TextEditingController amountController;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback? onDeposit;
  final VoidCallback? onWithdraw;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final due = DateTime.tryParse(goal.targetOn);
    final progress = double.tryParse(goal.progressPercent) ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(goal.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              key: Key('savings-goal-amounts-${goal.goalId}'),
              '${goal.currentAmount} / ${goal.targetAmount} ${goal.currency}',
              style: theme.textTheme.bodyLarge,
            ),
            if (due != null) ...[
              const SizedBox(height: 4),
              Text(
                materialL10n.formatMediumDate(due),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            // The bar repeats what the amounts already say, so progress is
            // never carried by a visual alone.
            LinearProgressIndicator(
              value: (progress / 100).clamp(0.0, 1.0),
              semanticsLabel: l10n.savingsGoalTitle,
              semanticsValue: '${goal.progressPercent}%',
            ),
            if (goal.achieved) ...[
              const SizedBox(height: 8),
              Text(
                l10n.savingsGoalAchievedLabel,
                key: Key('savings-goal-achieved-${goal.goalId}'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: Key('savings-goal-amount-${goal.goalId}'),
              controller: amountController,
              enabled: !isBusy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.savingsGoalContributionLabel,
                suffixText: goal.currency,
              ),
              onChanged: onAmountChanged,
            ),
            const SizedBox(height: 12),
            if (isBusy)
              const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  Semantics(
                    button: true,
                    label: l10n.savingsGoalDepositSemantics,
                    child: FilledButton.tonal(
                      key: Key('savings-goal-deposit-${goal.goalId}'),
                      onPressed: onDeposit,
                      child: Text(l10n.savingsGoalDepositAction),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l10n.savingsGoalWithdrawSemantics,
                    child: OutlinedButton(
                      key: Key('savings-goal-withdraw-${goal.goalId}'),
                      onPressed: onWithdraw,
                      child: Text(l10n.savingsGoalWithdrawAction),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l10n.savingsGoalCancelSemantics,
                    child: TextButton(
                      key: Key('savings-goal-cancel-${goal.goalId}'),
                      onPressed: onCancel,
                      child: Text(l10n.savingsGoalCancelAction),
                    ),
                  ),
                ],
              ),
          ],
        ),
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
