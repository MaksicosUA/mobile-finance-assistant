import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/widgets/refreshable_message.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../finance_entry/domain/finance_entry_models.dart';
import '../../home/domain/home_snapshot.dart';
import '../../home/presentation/money_formatter.dart';
import '../application/budgets_controller.dart';

/// Monthly ceilings and how the month stands against them (ADR 0027).
///
/// Nothing here is computed. The limit is the only number this screen sends;
/// spent, remaining and overspent arrive already derived, so this screen and
/// Analytics cannot disagree about the same month.
class BudgetsPage extends ConsumerStatefulWidget {
  const BudgetsPage({required this.onSignInRequested, super.key});

  final Future<void> Function() onSignInRequested;

  @override
  ConsumerState<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends ConsumerState<BudgetsPage> {
  bool _signInRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(budgetsControllerProvider.notifier).load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(budgetsControllerProvider);

    if (state is BudgetsAuthenticationRequired && !_signInRequested) {
      _signInRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await widget.onSignInRequested();
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.budgetsTitle)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: ref.read(budgetsControllerProvider.notifier).refresh,
          child: switch (state) {
            BudgetsLoading() ||
            BudgetsAuthenticationRequired() => const RefreshableMessage(
              key: Key('budgets-loading'),
              child: CircularProgressIndicator.adaptive(),
            ),
            BudgetsAccountRequired() => RefreshableMessage(
              key: const Key('budgets-account-required'),
              child: Text(
                l10n.budgetsAccountRequired,
                textAlign: TextAlign.center,
              ),
            ),
            BudgetsFailure() => RefreshableMessage(
              key: const Key('budgets-failure'),
              child: Text(l10n.budgetsLoadError, textAlign: TextAlign.center),
            ),
            BudgetsReady() => _ready(context, l10n, state),
          },
        ),
      ),
    );
  }

  Widget _ready(
    BuildContext context,
    AppLocalizations l10n,
    BudgetsReady state,
  ) {
    final materialL10n = MaterialLocalizations.of(context);
    final privacy = ref.watch(appSettingsControllerProvider).privacyMode;
    final locale = Localizations.localeOf(context).toString();
    final from = DateTime.tryParse(state.snapshot.periodFrom);
    final to = DateTime.tryParse(state.snapshot.periodTo);

    return ListView(
      key: const Key('budgets-ready'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (from != null && to != null)
          Text(
            l10n.budgetsPeriod(
              materialL10n.formatMediumDate(from),
              materialL10n.formatMediumDate(to),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: AppSpacing.sm),
        if (state.snapshot.isEmpty)
          _Empty(l10n: l10n)
        else ...[
          if (state.snapshot.overall case final overall?) ...[
            _BudgetCard(
              key: const Key('budget-overall'),
              budget: overall,
              title: l10n.budgetsOverallTitle,
              currency: state.snapshot.currency,
              privacy: privacy,
              locale: locale,
              isBusy: state.busyBudgetId == overall.budgetId,
              onRemove: () => _confirmRemoval(context, l10n, overall.budgetId),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          ...state.snapshot.categories.map(
            (budget) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _BudgetCard(
                key: Key('budget-${budget.budgetId}'),
                budget: budget,
                title: budget.name ?? l10n.budgetsOverallTitle,
                currency: state.snapshot.currency,
                privacy: privacy,
                locale: locale,
                isBusy: state.busyBudgetId == budget.budgetId,
                onRemove: () => _confirmRemoval(context, l10n, budget.budgetId),
              ),
            ),
          ),
        ],
        if (state.failure != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            key: const Key('budgets-message'),
            l10n.budgetsWriteError,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const Key('budgets-add'),
          onPressed: state.isSubmitting
              ? null
              : () => _openEditor(context, state),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.budgetsAddAction),
        ),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context, BudgetsReady state) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BudgetEditor(state: state),
    );
  }

  Future<void> _confirmRemoval(
    BuildContext context,
    AppLocalizations l10n,
    String budgetId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.budgetsRemoveDialogTitle),
        content: Text(l10n.budgetsRemoveDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            key: const Key('confirm-remove-budget'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.budgetsRemoveAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(budgetsControllerProvider.notifier).removeBudget(budgetId);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('budgets-empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.budgetsEmpty, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.budgetsEmptyHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.budget,
    required this.title,
    required this.currency,
    required this.privacy,
    required this.locale,
    required this.isBusy,
    required this.onRemove,
    super.key,
  });

  final Budget budget;
  final String title;
  final String currency;
  final bool privacy;
  final String locale;
  final bool isBusy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final spent = _money(budget.spent);
    final limit = _money(budget.limit);
    final remaining = _money(_unsigned(budget.remaining));
    final progress = _progress();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (isBusy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                else
                  TextButton(
                    key: Key('budget-remove-${budget.budgetId}'),
                    onPressed: onRemove,
                    child: Text(l10n.budgetsRemoveAction),
                  ),
              ],
            ),
            Text(l10n.budgetsSpentOfLimit(spent, limit)),
            const SizedBox(height: AppSpacing.xs),
            // Clamped: a bar cannot show more than full, and the words below
            // carry the overspend. Never colour alone.
            LinearProgressIndicator(
              value: progress,
              color: budget.overspent ? scheme.error : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              key: Key('budget-remaining-${budget.budgetId}'),
              budget.overspent
                  ? l10n.budgetsOverspentBy(remaining)
                  : l10n.budgetsRemaining(remaining),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: budget.overspent ? scheme.error : null,
              ),
            ),
            if (_isPositive(budget.planned))
              Text(
                key: Key('budget-planned-${budget.budgetId}'),
                // Beside the remainder, never inside it (ADR 0018, ADR 0027).
                l10n.budgetsPlanned(_money(budget.planned)),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  double? _progress() {
    final limit = double.tryParse(budget.limit);
    final spent = double.tryParse(budget.spent);
    if (limit == null || spent == null || limit <= 0) return null;
    return (spent / limit).clamp(0.0, 1.0);
  }

  String _money(String amount) => MoneyFormatter.format(
    Money(amount: amount, currency: currency),
    locale: locale,
    privacy: privacy,
  );

  static String _unsigned(String amount) =>
      amount.startsWith('-') ? amount.substring(1) : amount;

  static bool _isPositive(String amount) {
    final value = double.tryParse(amount);
    return value != null && value > 0;
  }
}

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor({required this.state});

  final BudgetsReady state;

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  final TextEditingController _limit = TextEditingController();
  String? _categoryId;
  bool _overall = false;

  @override
  void initState() {
    super.initState();
    // Default to the overall ceiling only when it is the one still available.
    _overall =
        !widget.state.hasOverallBudget &&
        widget.state.categoriesWithoutBudget.isEmpty;
    _categoryId = widget.state.categoriesWithoutBudget.firstOrNull?.categoryId;
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = widget.state.categoriesWithoutBudget;
    final canPickOverall = !widget.state.hasOverallBudget;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('budget-editor'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.budgetsAddAction,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              if (available.isEmpty && !canPickOverall)
                Text(
                  l10n.budgetsNoCategoriesLeft,
                  key: const Key('budget-editor-nothing-left'),
                )
              else ...[
                DropdownButtonFormField<String?>(
                  key: const Key('budget-editor-target'),
                  initialValue: _overall ? null : _categoryId,
                  decoration: InputDecoration(
                    labelText: l10n.budgetsCategoryLabel,
                  ),
                  items: [
                    if (canPickOverall)
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(l10n.budgetsOverallTitle),
                      ),
                    for (final category in available)
                      DropdownMenuItem<String?>(
                        value: category.categoryId,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _overall = value == null;
                    _categoryId = value;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('budget-editor-limit'),
                  controller: _limit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.budgetsLimitLabel,
                    suffixText: widget.state.account.currency,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  key: const Key('budget-editor-save'),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await ref
                        .read(budgetsControllerProvider.notifier)
                        .setBudget(
                          categoryId: _overall ? null : _categoryId,
                          limit: _limit.text,
                        );
                    if (navigator.mounted) navigator.pop();
                  },
                  child: Text(l10n.budgetsSaveAction),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
