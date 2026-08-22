import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/refreshable_message.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/category_management_controller.dart';

import '../domain/finance_entry_models.dart';
import 'category_keywords_page.dart';
import '../domain/finance_entry_result.dart';
import 'widgets/category_picker.dart';

/// Manages the user's own categories (ADR 0020, step 2b).
///
/// Removal is hiding, never deletion. A hidden category stops being offered for
/// new operations and keeps every operation already recorded against it, which
/// is why the screen says so rather than leaving the user to guess.
class CategoryManagementPage extends ConsumerStatefulWidget {
  const CategoryManagementPage({required this.onSignInRequested, super.key});

  final Future<void> Function() onSignInRequested;

  @override
  ConsumerState<CategoryManagementPage> createState() =>
      _CategoryManagementPageState();
}

class _CategoryManagementPageState
    extends ConsumerState<CategoryManagementPage> {
  final TextEditingController _newName = TextEditingController();
  final TextEditingController _editedName = TextEditingController();
  bool _signInRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(categoryManagementControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _newName.dispose();
    _editedName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(categoryManagementControllerProvider);

    if (state is CategoryManagementAuthenticationRequired &&
        !_signInRequested) {
      _signInRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await widget.onSignInRequested();
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.categoriesTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RefreshIndicator(
            onRefresh: () => _refresh(l10n),
            child: switch (state) {
              CategoryManagementLoading() => const RefreshableMessage(
                key: Key('categories-loading'),
                child: CircularProgressIndicator.adaptive(),
              ),
              CategoryManagementAuthenticationRequired() =>
                const RefreshableMessage(
                  key: Key('categories-authentication'),
                  child: CircularProgressIndicator.adaptive(),
                ),
              CategoryManagementFailure() => RefreshableMessage(
                key: const Key('categories-failure'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.categoryLoadError, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref
                          .read(categoryManagementControllerProvider.notifier)
                          .load(),
                      child: Text(l10n.retryAction),
                    ),
                  ],
                ),
              ),
              CategoryManagementReady() => _ready(context, l10n, state),
            },
          ),
        ),
      ),
    );
  }

  /// A failed refresh keeps the catalogue that is already on screen, so the
  /// only way the user learns it failed is to be told.
  Future<void> _refresh(AppLocalizations l10n) async {
    final refreshed = await ref
        .read(categoryManagementControllerProvider.notifier)
        .refresh();
    if (refreshed || !mounted) return;
    if (ref.read(categoryManagementControllerProvider)
        is! CategoryManagementReady) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.categoryLoadError)));
  }

  Widget _ready(
    BuildContext context,
    AppLocalizations l10n,
    CategoryManagementReady state,
  ) {
    final controller = ref.read(categoryManagementControllerProvider.notifier);
    final offered = state.offered;
    final hidden = state.hidden;
    final enabled = !state.isSubmitting;

    return ListView(
      key: const Key('categories-page'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        SegmentedButton<FinanceOperationType>(
          key: const Key('categories-direction'),
          segments: [
            ButtonSegment(
              value: FinanceOperationType.expense,
              label: Text(l10n.categoriesExpenseTab),
            ),
            ButtonSegment(
              value: FinanceOperationType.income,
              label: Text(l10n.categoriesIncomeTab),
            ),
          ],
          selected: {state.direction},
          onSelectionChanged: enabled
              ? (selection) => controller.selectDirection(selection.first)
              : null,
        ),
        const SizedBox(height: 16),
        if (state.failure != null) ...[
          _FailureNote(failure: state.failure!),
          const SizedBox(height: 16),
        ],
        if (state.isCreating)
          _NameForm(
            key: const Key('categories-create-form'),
            controller: _newName,
            label: l10n.categoryNameLabel,
            submitLabel: l10n.categoryCreateAction,
            fieldKey: const Key('categories-new-name'),
            submitKey: const Key('categories-create-submit'),
            enabled: enabled,
            onChanged: controller.setNewName,
            onSubmit: controller.submitCreate,
            onCancel: controller.cancelCreating,
          )
        else
          OutlinedButton.icon(
            key: const Key('categories-add'),
            onPressed: enabled
                ? () {
                    _newName.clear();
                    controller.startCreating();
                  }
                : null,
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.categoryAddAction),
          ),
        const SizedBox(height: 16),
        if (offered.isEmpty)
          Padding(
            key: const Key('categories-empty'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l10n.categoryListEmpty, textAlign: TextAlign.center),
          ),
        for (final category in offered)
          _CategoryRow(
            category: category,
            l10n: l10n,
            isEditing: state.editingCategoryId == category.categoryId,
            isBusy: state.busyCategoryId == category.categoryId,
            enabled: enabled,
            editedName: _editedName,
            onStartRename: () {
              _editedName.text = category.name;
              controller.startRenaming(category);
            },
            onEditedName: controller.setEditedName,
            onSubmitRename: controller.submitRename,
            onCancelRename: controller.cancelRenaming,
            onHide: () => _confirmHide(context, l10n, category),
            onOpenKeywords: () => _openKeywords(context, category),
          ),
        if (hidden.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('categories-hidden-toggle'),
            onPressed: controller.toggleHidden,
            icon: Icon(
              state.showHidden
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
            label: Text(l10n.categoryHiddenSection(hidden.length)),
          ),
          if (state.showHidden) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.categoryHiddenNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final category in hidden)
              ListTile(
                key: Key('category-hidden-${category.categoryId}'),
                contentPadding: EdgeInsets.zero,
                title: Text(categoryLabel(l10n, _asCategory(category))),
                trailing: state.busyCategoryId == category.categoryId
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : TextButton(
                        key: Key('category-restore-${category.categoryId}'),
                        onPressed: enabled
                            ? () => controller.restore(category)
                            : null,
                        child: Text(l10n.categoryRestoreAction),
                      ),
              ),
          ],
        ],
      ],
    );
  }

  void _openKeywords(BuildContext context, ManagedFinanceCategory category) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CategoryKeywordsPage(
          categoryId: category.categoryId,
          categoryName: categoryLabel(
            AppLocalizations.of(context),
            _asCategory(category),
          ),
          onSignInRequested: widget.onSignInRequested,
        ),
      ),
    );
  }

  Future<void> _confirmHide(
    BuildContext context,
    AppLocalizations l10n,
    ManagedFinanceCategory category,
  ) async {
    final controller = ref.read(categoryManagementControllerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.categoryHideDialogTitle),
        content: Text(l10n.categoryHideDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            key: const Key('category-hide-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.categoryHideAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.archive(category);
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.l10n,
    required this.isEditing,
    required this.isBusy,
    required this.enabled,
    required this.editedName,
    required this.onStartRename,
    required this.onEditedName,
    required this.onSubmitRename,
    required this.onCancelRename,
    required this.onHide,
    required this.onOpenKeywords,
  });

  final ManagedFinanceCategory category;
  final AppLocalizations l10n;
  final bool isEditing;
  final bool isBusy;
  final bool enabled;
  final TextEditingController editedName;
  final VoidCallback onStartRename;
  final ValueChanged<String> onEditedName;
  final Future<void> Function() onSubmitRename;
  final VoidCallback onCancelRename;
  final Future<void> Function() onHide;
  final VoidCallback onOpenKeywords;

  @override
  Widget build(BuildContext context) {
    if (isEditing) {
      return _NameForm(
        key: Key('category-rename-form-${category.categoryId}'),
        controller: editedName,
        label: l10n.categoryNameLabel,
        submitLabel: l10n.categorySaveAction,
        fieldKey: Key('category-rename-field-${category.categoryId}'),
        submitKey: Key('category-rename-submit-${category.categoryId}'),
        enabled: enabled,
        onChanged: onEditedName,
        onSubmit: onSubmitRename,
        onCancel: onCancelRename,
      );
    }
    return ListTile(
      key: Key('category-row-${category.categoryId}'),
      contentPadding: EdgeInsets.zero,
      title: Text(categoryLabel(l10n, _asCategory(category))),
      trailing: isBusy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('category-keywords-${category.categoryId}'),
                  onPressed: enabled ? onOpenKeywords : null,
                  tooltip: l10n.categoryKeywordsAction,
                  icon: const Icon(Icons.tag_outlined),
                ),
                IconButton(
                  key: Key('category-rename-${category.categoryId}'),
                  onPressed: enabled ? onStartRename : null,
                  tooltip: l10n.categoryRenameAction,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: Key('category-hide-${category.categoryId}'),
                  onPressed: enabled ? onHide : null,
                  tooltip: l10n.categoryHideAction,
                  icon: const Icon(Icons.visibility_off_outlined),
                ),
              ],
            ),
    );
  }
}

class _NameForm extends StatelessWidget {
  const _NameForm({
    required this.controller,
    required this.label,
    required this.submitLabel,
    required this.fieldKey,
    required this.submitKey,
    required this.enabled,
    required this.onChanged,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String submitLabel;
  final Key fieldKey;
  final Key submitKey;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            maxLength: 100,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: label),
            onChanged: onChanged,
            onSubmitted: enabled ? (_) => onSubmit() : null,
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: enabled ? onCancel : null,
                child: Text(AppLocalizations.of(context).cancelAction),
              ),
              FilledButton(
                key: submitKey,
                onPressed: enabled ? onSubmit : null,
                child: Text(submitLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FailureNote extends StatelessWidget {
  const _FailureNote({required this.failure});

  final FinanceEntryFailure failure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      key: const Key('categories-failure-note'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Never colour alone: the icon carries the same meaning for anyone who
        // cannot distinguish it.
        Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _message(l10n, failure),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  String _message(AppLocalizations l10n, FinanceEntryFailure failure) {
    return switch (failure.code) {
      FinanceEntryErrorCode.categoryNameTaken => l10n.categoryNameTakenError,
      FinanceEntryErrorCode.categoryArchived => l10n.categoryArchivedError,
      FinanceEntryErrorCode.categoryNotFound => l10n.categoryNotFoundError,
      _ =>
        failure.kind == FinanceEntryFailureKind.invalidInput
            ? l10n.categoryNameInvalidError
            : l10n.categoryLoadError,
    };
  }
}

/// Reuses the picker's label rule: a seeded key renders as a localized name,
/// and anything the user renamed keeps the name they chose.
FinanceCategory _asCategory(ManagedFinanceCategory category) => FinanceCategory(
  categoryId: category.categoryId,
  name: category.name,
  direction: category.direction,
  systemKey: category.systemKey,
);
