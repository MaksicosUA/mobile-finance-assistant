import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/network/api_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/category_catalogue_controller.dart';
import '../application/finance_entry_controller.dart';
import '../application/text_entry_controller.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'widgets/category_picker.dart';

class FinanceEntryPage extends ConsumerStatefulWidget {
  const FinanceEntryPage({
    super.key,
    required this.onBackHome,
    required this.onSignInRequested,
    this.deliveryLocked = false,
  });

  final VoidCallback onBackHome;
  final VoidCallback onSignInRequested;
  final bool deliveryLocked;

  @override
  ConsumerState<FinanceEntryPage> createState() => _FinanceEntryPageState();
}

class _FinanceEntryPageState extends ConsumerState<FinanceEntryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(financeEntryControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(authAccountEpochProvider, (previous, next) {
      if (previous == null || previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(financeEntryControllerProvider.notifier).load();
        }
      });
    });
    final state = ref.watch(financeEntryControllerProvider);
    final privacy = ref.watch(appSettingsControllerProvider).privacyMode;
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.screenMaxWidth),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  0,
                ),
                child: Row(
                  children: [
                    IconButton.outlined(
                      key: const Key('finance-entry-back'),
                      onPressed: widget.onBackHome,
                      tooltip: l10n.backHome,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.financeEntryTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('finance-entry-page'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _FinanceEntryBody(
                    state: state,
                    privacyEnabled: privacy,
                    deliveryLocked: widget.deliveryLocked,
                    onBackHome: widget.onBackHome,
                    onSignInRequested: widget.onSignInRequested,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinanceEntryBody extends ConsumerWidget {
  const _FinanceEntryBody({
    required this.state,
    required this.privacyEnabled,
    required this.deliveryLocked,
    required this.onBackHome,
    required this.onSignInRequested,
  });

  final FinanceEntryState state;
  final bool privacyEnabled;
  final bool deliveryLocked;
  final VoidCallback onBackHome;
  final VoidCallback onSignInRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(financeEntryControllerProvider.notifier);
    return switch (state) {
      FinanceEntryLoading() => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Semantics(
          label: l10n.financeEntryLoading,
          child: const Center(child: CircularProgressIndicator()),
        ),
      ),
      FinanceEntryLoadFailure(:final failure) => _FailureCard(
        failure: failure,
        title: l10n.financeEntryLoadFailed,
        onRetry: controller.load,
      ),
      FinanceEntryAuthenticationRequired() => _MessageCard(
        key: const Key('finance-auth-required'),
        icon: Icons.lock_outline_rounded,
        title: l10n.authExpiredTitle,
        description: l10n.authExpiredDescription,
        actionLabel: l10n.signInAgainAction,
        onAction: onSignInRequested,
      ),
      FinanceAccountEditing() => _AccountForm(
        key: const ValueKey('account-form'),
        state: state as FinanceAccountEditing,
        privacyEnabled: privacyEnabled,
        onSubmit: controller.evaluateAccount,
      ),
      FinanceAccountReviewing() => _AccountReview(
        state: state as FinanceAccountReviewing,
        privacyEnabled: privacyEnabled,
        onEdit: controller.editAccount,
        onConfirm: controller.confirmAccount,
      ),
      FinanceOperationEditing() => _OperationForm(
        key: const ValueKey('operation-form'),
        state: state as FinanceOperationEditing,
        privacyEnabled: privacyEnabled,
        onSubmit: controller.evaluateOperation,
      ),
      FinanceOperationReviewing() => _OperationReview(
        state: state as FinanceOperationReviewing,
        privacyEnabled: privacyEnabled,
        onEdit: controller.editOperation,
        onConfirm: controller.confirmOperation,
      ),
      FinanceOperationAccepted() => _AcceptedOperation(
        state: state as FinanceOperationAccepted,
        onBackHome: onBackHome,
        onAddAnother: deliveryLocked ? null : controller.addAnotherOperation,
      ),
      FinanceOperationQueued(:final authenticationRequired) =>
        _OperationDeliveryCard(
          cardKey: const Key('operation-queued'),
          icon: Icons.cloud_upload_outlined,
          title: l10n.operationQueuedTitle,
          description: authenticationRequired
              ? l10n.operationQueuedAuthDescription
              : l10n.operationQueuedDescription,
          primaryLabel: authenticationRequired
              ? l10n.signInAgainAction
              : l10n.backHome,
          onPrimary: authenticationRequired ? onSignInRequested : onBackHome,
          onAddAnother: deliveryLocked ? null : controller.addAnotherOperation,
        ),
      FinanceOperationAlreadySynced() => _OperationDeliveryCard(
        cardKey: const Key('operation-already-synced'),
        icon: Icons.verified_outlined,
        title: l10n.operationAlreadySyncedTitle,
        description: l10n.operationAlreadySyncedDescription,
        primaryLabel: l10n.backHome,
        onPrimary: onBackHome,
        onAddAnother: deliveryLocked ? null : controller.addAnotherOperation,
      ),
      FinanceOperationDeliveryAttention(:final issue) => _OperationDeliveryCard(
        cardKey: const Key('operation-delivery-attention'),
        icon: Icons.report_gmailerrorred_rounded,
        title: l10n.operationAttentionTitle,
        description: _deliveryIssueMessage(l10n, issue),
        primaryLabel: l10n.backHome,
        onPrimary: onBackHome,
        onAddAnother:
            deliveryLocked ||
                issue == FinanceOperationDeliveryIssue.securityBlocked
            ? null
            : controller.addAnotherOperation,
      ),
    };
  }
}

class _AccountForm extends StatefulWidget {
  const _AccountForm({
    super.key,
    required this.state,
    required this.privacyEnabled,
    required this.onSubmit,
  });

  final FinanceAccountEditing state;
  final bool privacyEnabled;
  final ValueChanged<AccountSetupInput> onSubmit;

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late DateTime _openingDate;
  bool _validateContinuously = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.state.initialInput.name,
    );
    _balanceController = TextEditingController(
      text: widget.state.initialInput.openingBalance,
    );
    _openingDate = widget.state.initialInput.openingBalanceOn;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      autovalidateMode: _validateContinuously
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Intro(
            icon: Icons.account_balance_wallet_outlined,
            title: l10n.accountSetupTitle,
            description: l10n.accountSetupDescription,
          ),
          if (widget.state.failure != null ||
              widget.state.issues.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _FinanceMessage(
              failure: widget.state.failure,
              issues: widget.state.issues,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            key: const Key('account-name'),
            controller: _nameController,
            enabled: !widget.state.isSubmitting,
            maxLength: 100,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.accountNameField,
              hintText: l10n.accountNameHint,
              counterText: '',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? l10n.accountNameRequired
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: const Key('opening-balance'),
            controller: _balanceController,
            enabled: !widget.state.isSubmitting,
            obscureText: widget.privacyEnabled,
            enableSuggestions: false,
            autocorrect: false,
            enableInteractiveSelection: !widget.privacyEnabled,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.openingBalanceField,
              suffixText: 'EUR',
              helperText: l10n.openingBalanceHelp,
            ),
            validator: (value) {
              try {
                normalizeMoneyInput(value ?? '', allowNegative: true);
                return null;
              } on FormatException {
                return l10n.moneyInputInvalid;
              }
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _DateField(
            key: const Key('opening-date'),
            label: l10n.openingBalanceDateField,
            value: _openingDate,
            firstDate: DateTime(1900),
            lastDate: widget.state.latestOpeningDate,
            enabled: !widget.state.isSubmitting,
            onChanged: (value) => setState(() => _openingDate = value),
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            label: l10n.canonicalTimezoneLabel,
            value: configuredHomeApiTimezone,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const Key('account-evaluate'),
            onPressed: widget.state.isSubmitting ? null : _submit,
            child: widget.state.isSubmitting
                ? const _ButtonProgress()
                : Text(l10n.continueToReviewAction),
          ),
        ],
      ),
    );
  }

  void _submit() {
    setState(() => _validateContinuously = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSubmit(
      AccountSetupInput(
        name: _nameController.text,
        openingBalance: _balanceController.text,
        openingBalanceOn: _openingDate,
      ),
    );
  }
}

class _OperationForm extends ConsumerStatefulWidget {
  const _OperationForm({
    super.key,
    required this.state,
    required this.privacyEnabled,
    required this.onSubmit,
  });

  final FinanceOperationEditing state;
  final bool privacyEnabled;
  final ValueChanged<OperationEntryInput> onSubmit;

  @override
  ConsumerState<_OperationForm> createState() => _OperationFormState();
}

class _OperationFormState extends ConsumerState<_OperationForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _categoryController;
  late final TextEditingController _merchantController;
  late final TextEditingController _sentenceController;
  late FinanceOperationType _type;
  late DateTime _occurredOn;
  CategoryChoice _categoryChoice = const CategoryUnset();
  bool _validateContinuously = false;

  @override
  void initState() {
    super.initState();
    final input = widget.state.initialInput;
    _amountController = TextEditingController(text: input.amount);
    _categoryController = TextEditingController(text: input.category);
    _merchantController = TextEditingController(text: input.merchant);
    _sentenceController = TextEditingController();
    _type = input.type;
    _occurredOn = input.occurredOn;
    if ((input.category ?? '').isNotEmpty && input.categoryId == null) {
      _categoryChoice = const CategoryFreeText();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(categoryCatalogueProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _categoryController.dispose();
    _merchantController.dispose();
    _sentenceController.dispose();
    super.dispose();
  }

  /// Fills the form from a proposal. It fills fields and nothing else: the
  /// operation is still written by the ordinary confirm path below (ADR 0022).
  void _applyProposal(OperationProposal proposal) {
    final catalogue = ref.read(categoryCatalogueProvider.notifier);
    setState(() {
      _type = proposal.type;
      // A missing amount leaves whatever is already typed alone: the parser
      // reporting a gap must not erase the user's own correction.
      final amount = proposal.amount;
      if (amount != null) _amountController.text = amount;
      final occurredOn = DateTime.tryParse('${proposal.occurredOn}T00:00:00Z');
      if (occurredOn != null) _occurredOn = occurredOn;
      final categoryId = proposal.categoryId;
      if (categoryId == null) return;
      for (final category in catalogue.forDirection(proposal.type)) {
        if (category.categoryId != categoryId) continue;
        _categoryChoice = CategoryFromCatalogue(category);
        _categoryController.clear();
        return;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final account = widget.state.account;
    final textEntry = ref.watch(textEntryControllerProvider);
    ref.listen<TextEntryState>(textEntryControllerProvider, (previous, next) {
      if (next is TextEntryParsed) _applyProposal(next.proposal);
    });
    return Form(
      key: _formKey,
      autovalidateMode: _validateContinuously
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Intro(
            icon: Icons.edit_note_rounded,
            title: l10n.manualOperationTitle,
            description: l10n.manualOperationDescription,
          ),
          const SizedBox(height: AppSpacing.md),
          _SentenceField(
            controller: _sentenceController,
            state: textEntry,
            enabled: !widget.state.isSubmitting,
            onParse: () => ref
                .read(textEntryControllerProvider.notifier)
                .parse(_sentenceController.text),
          ),
          if (widget.state.accountCreated) ...[
            const SizedBox(height: AppSpacing.md),
            _StatusMessage(
              key: const Key('account-created-message'),
              icon: Icons.check_circle_outline_rounded,
              message: l10n.accountCreatedNotice,
            ),
          ],
          if (widget.state.failure != null ||
              widget.state.issues.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _FinanceMessage(
              failure: widget.state.failure,
              issues: widget.state.issues,
              openingBalanceOn: account.openingBalanceOn,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _InfoRow(label: l10n.accountLabel, value: account.name),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<FinanceOperationType>(
            key: const Key('operation-type'),
            segments: [
              ButtonSegment(
                value: FinanceOperationType.expense,
                icon: const Icon(Icons.south_east_rounded),
                label: Text(l10n.operationExpense),
              ),
              ButtonSegment(
                value: FinanceOperationType.income,
                icon: const Icon(Icons.north_west_rounded),
                label: Text(l10n.operationIncome),
              ),
            ],
            selected: {_type},
            onSelectionChanged: widget.state.isSubmitting
                ? null
                : (values) => setState(() {
                    _type = values.single;
                    // Categories are typed by direction, so a selection made
                    // for an expense cannot survive a switch to income — it
                    // would be submitted against the wrong catalogue and
                    // rejected.
                    if (_categoryChoice is CategoryFromCatalogue) {
                      _categoryChoice = const CategoryUnset();
                    }
                  }),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('operation-amount'),
            controller: _amountController,
            enabled: !widget.state.isSubmitting,
            obscureText: widget.privacyEnabled,
            enableSuggestions: false,
            autocorrect: false,
            enableInteractiveSelection: !widget.privacyEnabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.operationAmountField,
              suffixText: account.currency,
            ),
            validator: (value) {
              try {
                normalizeMoneyInput(value ?? '');
                return null;
              } on FormatException {
                return l10n.positiveMoneyInputInvalid;
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: const Key('operation-merchant'),
            controller: _merchantController,
            enabled: !widget.state.isSubmitting,
            maxLength: 160,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.merchantField,
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          CategoryPicker(
            categories: ref
                .watch(categoryCatalogueProvider.notifier)
                .forDirection(_type),
            choice: _categoryChoice,
            freeTextController: _categoryController,
            enabled: !widget.state.isSubmitting,
            catalogueUnavailable:
                ref.watch(categoryCatalogueProvider)
                    is CategoryCatalogueUnavailable,
            onChanged: (choice) => setState(() {
              _categoryChoice = choice;
              // Leaving free text behind would send a name the chosen category
              // does not have.
              if (choice is! CategoryFreeText) _categoryController.clear();
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          _DateField(
            key: const Key('operation-date'),
            label: l10n.operationDateField,
            value: _occurredOn,
            firstDate: DateTime.parse('${account.openingBalanceOn}T00:00:00Z'),
            lastDate: widget.state.latestOperationDate,
            enabled: !widget.state.isSubmitting,
            onChanged: (value) => setState(() => _occurredOn = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const Key('operation-evaluate'),
            onPressed: widget.state.isSubmitting ? null : _submit,
            child: widget.state.isSubmitting
                ? const _ButtonProgress()
                : Text(l10n.continueToReviewAction),
          ),
        ],
      ),
    );
  }

  void _submit() {
    setState(() => _validateContinuously = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final choice = _categoryChoice;
    widget.onSubmit(
      OperationEntryInput(
        type: _type,
        amount: _amountController.text,
        occurredOn: _occurredOn,
        // A chosen category sends its own name, so the stored text always says
        // what the user picked (ADR 0020).
        category: switch (choice) {
          CategoryFromCatalogue(:final category) => category.name,
          CategoryFreeText() => _categoryController.text,
          CategoryUnset() => '',
        },
        categoryId: switch (choice) {
          CategoryFromCatalogue(:final category) => category.categoryId,
          _ => null,
        },
        merchant: _merchantController.text,
      ),
    );
  }
}

class _AccountReview extends StatelessWidget {
  const _AccountReview({
    required this.state,
    required this.privacyEnabled,
    required this.onEdit,
    required this.onConfirm,
  });

  final FinanceAccountReviewing state;
  final bool privacyEnabled;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = state.review.draft;
    return _ReviewCard(
      title: l10n.accountReviewTitle,
      description: l10n.reviewBeforeConfirmDescription,
      failure: state.failure,
      rows: [
        _ReviewValue(l10n.accountLabel, draft.name),
        _ReviewValue(
          l10n.openingBalanceField,
          _exactMoney(draft.openingBalance, draft.currency, privacyEnabled),
          isMoney: true,
        ),
        _ReviewValue(
          l10n.openingBalanceDateField,
          _localizedDate(context, draft.openingBalanceOn),
        ),
        _ReviewValue(l10n.canonicalTimezoneLabel, draft.canonicalTimezone),
      ],
      submitting: state.isSubmitting,
      onEdit: onEdit,
      onConfirm: onConfirm,
    );
  }
}

class _OperationReview extends StatelessWidget {
  const _OperationReview({
    required this.state,
    required this.privacyEnabled,
    required this.onEdit,
    required this.onConfirm,
  });

  final FinanceOperationReviewing state;
  final bool privacyEnabled;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = state.review.draft;
    return _ReviewCard(
      title: l10n.operationReviewTitle,
      description: l10n.reviewBeforeConfirmDescription,
      failure: state.failure,
      rows: [
        _ReviewValue(
          l10n.operationTypeLabel,
          draft.type == FinanceOperationType.expense
              ? l10n.operationExpense
              : l10n.operationIncome,
        ),
        _ReviewValue(
          l10n.operationAmountField,
          _exactMoney(draft.amount, draft.currency, privacyEnabled),
          isMoney: true,
        ),
        _ReviewValue(l10n.accountLabel, state.account.name),
        if (draft.merchant != null)
          _ReviewValue(l10n.merchantField, draft.merchant!),
        if (draft.category != null)
          _ReviewValue(l10n.categoryField, draft.category!),
        _ReviewValue(
          l10n.operationDateField,
          _localizedDate(context, draft.occurredOn),
        ),
      ],
      submitting: state.isSubmitting,
      onEdit: onEdit,
      onConfirm: onConfirm,
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.title,
    required this.description,
    required this.failure,
    required this.rows,
    required this.submitting,
    required this.onEdit,
    required this.onConfirm,
  });

  final String title;
  final String description;
  final FinanceEntryFailure? failure;
  final List<_ReviewValue> rows;
  final bool submitting;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Intro(
          icon: Icons.fact_check_outlined,
          title: title,
          description: description,
        ),
        if (failure != null) ...[
          const SizedBox(height: AppSpacing.md),
          _FinanceMessage(failure: failure),
        ],
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  _ReviewRow(value: rows[index]),
                  if (index != rows.length - 1)
                    Divider(
                      height: AppSpacing.lg,
                      color: context.appColors.border,
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          key: const Key('finance-confirm'),
          onPressed: submitting ? null : onConfirm,
          child: submitting
              ? const _ButtonProgress()
              : Text(l10n.confirmFinanceAction),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          key: const Key('finance-edit'),
          onPressed: submitting ? null : onEdit,
          child: Text(l10n.editAction),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.value});

  final _ReviewValue value;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            value.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            value.value,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    if (!value.isMoney) return content;
    return Semantics(
      label: '${value.label}: ${value.value}',
      excludeSemantics: true,
      child: content,
    );
  }
}

class _AcceptedOperation extends StatelessWidget {
  const _AcceptedOperation({
    required this.state,
    required this.onBackHome,
    this.onAddAnother,
  });

  final FinanceOperationAccepted state;
  final VoidCallback onBackHome;
  final VoidCallback? onAddAnother;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (description, icon) = switch (state.homeStatus) {
      FinanceEntryHomeStatus.updating => (
        l10n.operationAcceptedUpdatingHome,
        Icons.sync_rounded,
      ),
      FinanceEntryHomeStatus.updated => (
        l10n.operationAcceptedHomeUpdated,
        Icons.check_circle_outline_rounded,
      ),
      FinanceEntryHomeStatus.projectionDelayed => (
        l10n.operationAcceptedProjectionDelayed,
        Icons.schedule_rounded,
      ),
      FinanceEntryHomeStatus.authenticationRequired => (
        l10n.operationAcceptedAuthRequired,
        Icons.lock_clock_outlined,
      ),
      FinanceEntryHomeStatus.sessionChanged => (
        l10n.operationAcceptedSessionChanged,
        Icons.sync_problem_outlined,
      ),
      FinanceEntryHomeStatus.failed => (
        l10n.operationAcceptedRefreshFailed,
        Icons.cloud_off_outlined,
      ),
    };
    final updating = state.homeStatus == FinanceEntryHomeStatus.updating;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        key: const Key('operation-accepted'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Icon(
                icon,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.operationAcceptedTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(description, textAlign: TextAlign.center),
              if (updating) ...[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('operation-back-home'),
                onPressed: onBackHome,
                child: Text(l10n.backHome),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                key: const Key('operation-add-another'),
                onPressed: updating ? null : onAddAnother,
                child: Text(l10n.addAnotherOperationAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationDeliveryCard extends StatelessWidget {
  const _OperationDeliveryCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    this.onAddAnother,
  });

  final Key cardKey;
  final IconData icon;
  final String title;
  final String description;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onAddAnother;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        key: cardKey,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Icon(
                icon,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(description, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
              if (onAddAnother case final callback?) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: callback,
                  child: Text(l10n.addAnotherOperationAction),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({
    required this.failure,
    required this.title,
    required this.onRetry,
  });

  final FinanceEntryFailure failure;
  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _MessageCard(
      icon: Icons.error_outline_rounded,
      title: title,
      description: _failureMessage(l10n, failure),
      secondary: l10n.requestIdLabel(failure.requestId),
      actionLabel: l10n.retryAction,
      onAction: onRetry,
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    this.secondary,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? secondary;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Icon(
                icon,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(description, textAlign: TextAlign.center),
              if (secondary != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  secondary!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinanceMessage extends StatelessWidget {
  const _FinanceMessage({
    this.failure,
    this.issues = const [],
    this.openingBalanceOn,
  });

  final FinanceEntryFailure? failure;
  final List<FinanceIssue> issues;

  /// The account baseline, when known, so a refusal can name the actual bound.
  final String? openingBalanceOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localizedOpeningBalanceOn = openingBalanceOn == null
        ? null
        : _localizedDate(context, openingBalanceOn!);
    final message = failure == null
        ? _issuesMessage(
            l10n,
            issues,
            openingBalanceOn: localizedOpeningBalanceOn,
          )
        : _failureMessage(
            l10n,
            failure!,
            openingBalanceOn: localizedOpeningBalanceOn,
          );
    return _StatusMessage(
      key: const Key('finance-entry-message'),
      icon: Icons.info_outline_rounded,
      message: message,
      secondary: failure == null
          ? null
          : l10n.requestIdLabel(failure!.requestId),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    super.key,
    required this.icon,
    required this.message,
    this.secondary,
  });

  final IconData icon;
  final String message;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(color: context.appColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message),
                    if (secondary != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        secondary!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          description,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.appColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// One sentence in, a filled form out.
///
/// The sentence is read on the server and comes back as a proposal; nothing
/// here records anything. What it fills in stays editable, and the ordinary
/// confirmation below is still what writes the operation (ADR 0022).
class _SentenceField extends StatelessWidget {
  const _SentenceField({
    required this.controller,
    required this.state,
    required this.enabled,
    required this.onParse,
  });

  final TextEditingController controller;
  final TextEntryState state;
  final bool enabled;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parsing = state is TextEntryParsing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('operation-sentence'),
          controller: controller,
          enabled: enabled && !parsing,
          maxLength: maximumEntryTextLength,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onParse(),
          decoration: InputDecoration(
            labelText: l10n.entrySentenceField,
            hintText: l10n.entrySentenceHint,
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const Key('operation-sentence-parse'),
          onPressed: enabled && !parsing ? onParse : null,
          icon: parsing
              ? const _ButtonProgress()
              : const Icon(Icons.auto_awesome_outlined),
          label: Text(l10n.entrySentenceParseAction),
        ),
        if (state case final TextEntryFailed failed) ...[
          const SizedBox(height: AppSpacing.sm),
          _StatusMessage(
            key: const Key('operation-sentence-error'),
            icon: Icons.error_outline_rounded,
            message: failed.failure.kind == FinanceEntryFailureKind.invalidInput
                ? l10n.entrySentenceEmpty
                : l10n.entrySentenceParseError,
          ),
        ],
        if (state case final TextEntryParsed parsed) ...[
          const SizedBox(height: AppSpacing.sm),
          _StatusMessage(
            key: const Key('operation-sentence-result'),
            icon: parsed.proposal.gaps.isEmpty
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            // A gap is not a failure: it names the one field the parser
            // refused to guess, so the user knows what to look at.
            message: [
              l10n.entrySentenceFilled,
              for (final gap in parsed.proposal.gaps) _gapMessage(l10n, gap),
            ].join(' '),
          ),
        ],
      ],
    );
  }

  String _gapMessage(AppLocalizations l10n, OperationParseGap gap) {
    return switch (gap) {
      OperationParseGap.amountNotFound => l10n.entrySentenceGapAmount,
      OperationParseGap.ambiguousAmount => l10n.entrySentenceGapAmbiguous,
      OperationParseGap.dateNotUnderstood => l10n.entrySentenceGapDate,
      OperationParseGap.categoryNotMatched => l10n.entrySentenceGapCategory,
    };
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    super.key,
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final formatted = MaterialLocalizations.of(context).formatMediumDate(value);
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label, $formatted',
      excludeSemantics: true,
      onTap: enabled ? () => _pick(context) : null,
      child: OutlinedButton.icon(
        onPressed: enabled ? () => _pick(context) : null,
        icon: const Icon(Icons.calendar_today_outlined),
        label: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('$label: $formatted'),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    DateTime localDate(DateTime date) =>
        DateTime(date.year, date.month, date.day);
    final localFirstDate = localDate(firstDate);
    final localLastDate = localDate(lastDate);
    final localValue = localDate(value);
    final initialDate = localValue.isBefore(localFirstDate)
        ? localFirstDate
        : localValue.isAfter(localLastDate)
        ? localLastDate
        : localValue;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: localFirstDate,
      lastDate: localLastDate,
    );
    if (selected != null) onChanged(selected);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 24,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

final class _ReviewValue {
  const _ReviewValue(this.label, this.value, {this.isMoney = false});

  final String label;
  final String value;
  final bool isMoney;
}

String _exactMoney(String amount, String currency, bool privacy) {
  if (privacy) return '•••••• ${currency == 'EUR' ? '€' : currency}';
  final localized = amount.replaceFirst('.', ',').replaceFirst('-', '−');
  return '$localized ${currency == 'EUR' ? '€' : currency}';
}

String _localizedDate(BuildContext context, String wireDate) {
  final value = DateTime.parse('${wireDate}T00:00:00');
  return MaterialLocalizations.of(context).formatMediumDate(value);
}

String _issuesMessage(
  AppLocalizations l10n,
  List<FinanceIssue> issues, {
  String? openingBalanceOn,
}) {
  if (issues.any(
    (issue) =>
        issue.code == FinanceIssueCode.openingBalanceDateInFuture ||
        issue.code == FinanceIssueCode.futureOccurredDate,
  )) {
    return l10n.financeDateRejected;
  }
  if (issues.any(
    (issue) => issue.code == FinanceIssueCode.operationBeforeAccountBaseline,
  )) {
    // Name the bound and the way out instead of a bare range error (ADR 0016).
    final baseline = openingBalanceOn;
    if (baseline == null) return l10n.operationBeforeOpeningDateError;
    return l10n.operationBeforeOpeningDateDetail(baseline);
  }
  if (issues.any(
    (issue) =>
        issue.code == FinanceIssueCode.accountUnavailable ||
        issue.code == FinanceIssueCode.accountRequired,
  )) {
    return l10n.financeAccountUnavailable;
  }
  return l10n.financeValidationRejected;
}

String _failureMessage(
  AppLocalizations l10n,
  FinanceEntryFailure failure, {
  String? openingBalanceOn,
}) => switch (failure.kind) {
  FinanceEntryFailureKind.invalidInput => l10n.financeInvalidInput,
  FinanceEntryFailureKind.unauthenticated ||
  FinanceEntryFailureKind.unauthorized => l10n.authExpiredDescription,
  FinanceEntryFailureKind.sessionChanged => l10n.financeSessionChanged,
  FinanceEntryFailureKind.interrupted => l10n.operationPendingBannerDescription,
  FinanceEntryFailureKind.conflict => l10n.financeConflictError,
  FinanceEntryFailureKind.rejected => _issuesMessage(
    l10n,
    failure.issues,
    openingBalanceOn: openingBalanceOn,
  ),
  FinanceEntryFailureKind.offline => l10n.financeOfflineError,
  FinanceEntryFailureKind.timeout => l10n.financeTimeoutError,
  FinanceEntryFailureKind.serviceUnavailable => l10n.financeServiceError,
  FinanceEntryFailureKind.securityFailure => l10n.financeSecurityError,
  FinanceEntryFailureKind.localStorage => l10n.financeLocalStorageError,
  FinanceEntryFailureKind.malformedResponse ||
  FinanceEntryFailureKind.unknown => l10n.financeUnexpectedError,
};

String _deliveryIssueMessage(
  AppLocalizations l10n,
  FinanceOperationDeliveryIssue issue,
) => switch (issue) {
  FinanceOperationDeliveryIssue.commandConflict =>
    l10n.operationAttentionConflict,
  FinanceOperationDeliveryIssue.rejected => l10n.operationAttentionRejected,
  FinanceOperationDeliveryIssue.securityBlocked =>
    l10n.operationAttentionSecurity,
  FinanceOperationDeliveryIssue.invalidCommand =>
    l10n.operationAttentionInvalid,
};
