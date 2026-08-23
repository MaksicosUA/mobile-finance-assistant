import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/operation_correction_controller.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'widgets/category_picker.dart';

/// Correcting one confirmed operation (ADR 0023).
///
/// The original is never edited: confirming here withdraws it and writes the
/// replacement in one server transaction. Removing withdraws it with nothing
/// in its place.
class OperationCorrectionSheet extends ConsumerStatefulWidget {
  const OperationCorrectionSheet({
    required this.operation,
    required this.onSignInRequested,
    super.key,
  });

  final OperationHistoryItem operation;
  final Future<void> Function() onSignInRequested;

  @override
  ConsumerState<OperationCorrectionSheet> createState() =>
      _OperationCorrectionSheetState();
}

class _OperationCorrectionSheetState
    extends ConsumerState<OperationCorrectionSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _freeText = TextEditingController();
  bool _amountFilled = false;
  bool _signInRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(operationCorrectionControllerProvider.notifier)
          .open(widget.operation);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _freeText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(operationCorrectionControllerProvider);

    if (state is OperationCorrectionAuthenticationRequired &&
        !_signInRequested) {
      _signInRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        Navigator.of(context).pop();
        await widget.onSignInRequested();
      });
    }
    if (state is OperationCorrectionDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).pop(state.removed ? _Outcome.removed : _Outcome.corrected);
      });
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: switch (state) {
          OperationCorrectionLoading() ||
          OperationCorrectionAuthenticationRequired() ||
          OperationCorrectionDone() => const Padding(
            key: Key('correction-loading'),
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
          OperationCorrectionUnavailable() => Padding(
            key: const Key('correction-unavailable'),
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              l10n.operationCorrectionFailed,
              textAlign: TextAlign.center,
            ),
          ),
          OperationCorrectionEditing() => _form(context, l10n, state),
        },
      ),
    );
  }

  Widget _form(
    BuildContext context,
    AppLocalizations l10n,
    OperationCorrectionEditing state,
  ) {
    if (!_amountFilled) {
      _amount.text = state.amount;
      _amountFilled = true;
    }
    final controller = ref.read(operationCorrectionControllerProvider.notifier);
    final enabled = !state.isSubmitting;
    final chosen = state.categories
        .where((category) => category.categoryId == state.categoryId)
        .firstOrNull;

    return SingleChildScrollView(
      child: Column(
        key: const Key('correction-form'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.operationCorrectTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          SegmentedButton<FinanceOperationType>(
            key: const Key('correction-direction'),
            segments: [
              ButtonSegment(
                value: FinanceOperationType.expense,
                label: Text(l10n.operationExpense),
              ),
              ButtonSegment(
                value: FinanceOperationType.income,
                label: Text(l10n.operationIncome),
              ),
            ],
            selected: {state.type},
            onSelectionChanged: enabled
                ? (selection) => controller.editType(selection.first)
                : null,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('correction-amount'),
            controller: _amount,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.operationAmountField,
              suffixText: state.account.currency,
            ),
            onChanged: controller.editAmount,
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(labelText: l10n.operationDateField),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatFullDate(state.occurredOn),
                  ),
                ),
                TextButton(
                  key: const Key('correction-date'),
                  onPressed: enabled
                      ? () => _pickDate(context, state, controller)
                      : null,
                  child: Text(l10n.operationCorrectAction),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CategoryPicker(
            categories: state.categories
                .where((category) => category.direction == state.type)
                .toList(growable: false),
            choice: chosen == null
                ? const CategoryUnset()
                : CategoryFromCatalogue(chosen),
            freeTextController: _freeText,
            enabled: enabled,
            catalogueUnavailable: state.categories.isEmpty,
            onChanged: (choice) => controller.editCategory(
              // Free text is not offered here: a correction exists to put an
              // operation under a real category, and inventing one is the
              // catalogue's own screen (ADR 0020).
              choice is CategoryFromCatalogue
                  ? choice.category.categoryId
                  : null,
            ),
          ),
          if (state.issues.isNotEmpty || state.failure != null) ...[
            const SizedBox(height: 16),
            Text(
              key: const Key('correction-message'),
              _message(l10n, state),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('correction-save'),
            onPressed: enabled ? controller.submit : null,
            child: Text(l10n.operationCorrectSave),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('correction-remove'),
            onPressed: enabled ? () => _confirmRemoval(context, l10n) : null,
            child: Text(
              l10n.operationRemoveAction,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    OperationCorrectionEditing state,
    OperationCorrectionController controller,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: state.occurredOn,
      firstDate: DateTime.parse(state.account.openingBalanceOn),
      // The server refuses a future operation; offering one would only
      // produce a rejection the user has to read.
      lastDate: DateTime.now(),
    );
    if (picked != null) controller.editDate(picked);
  }

  Future<void> _confirmRemoval(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.operationRemoveDialogTitle),
        content: Text(l10n.operationRemoveDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            key: const Key('confirm-remove-operation'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.operationRemoveAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(operationCorrectionControllerProvider.notifier).remove();
  }

  String _message(AppLocalizations l10n, OperationCorrectionEditing state) {
    final failure = state.failure;
    if (failure != null) {
      return switch (failure.code) {
        FinanceEntryErrorCode.operationNotFound =>
          l10n.operationNotFoundMessage,
        FinanceEntryErrorCode.operationAlreadyReversed =>
          l10n.operationAlreadyReversedMessage,
        _ => l10n.operationCorrectionFailed,
      };
    }
    // A rejected replacement is refused for the same reasons a new operation
    // is, so it reads the same way: a future date is its own sentence, and
    // everything else points back at the fields.
    final futureDate = state.issues.any(
      (issue) => issue.code == FinanceIssueCode.futureOccurredDate,
    );
    return futureDate
        ? l10n.financeDateRejected
        : l10n.financeValidationRejected;
  }
}

enum _Outcome { corrected, removed }

/// Opens the sheet and reports what happened, so the caller can refresh.
Future<OperationCorrectionOutcome?> showOperationCorrectionSheet(
  BuildContext context, {
  required OperationHistoryItem operation,
  required Future<void> Function() onSignInRequested,
}) async {
  final outcome = await showModalBottomSheet<_Outcome>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => OperationCorrectionSheet(
      operation: operation,
      onSignInRequested: onSignInRequested,
    ),
  );
  return switch (outcome) {
    _Outcome.corrected => OperationCorrectionOutcome.corrected,
    _Outcome.removed => OperationCorrectionOutcome.removed,
    null => null,
  };
}

enum OperationCorrectionOutcome { corrected, removed }
