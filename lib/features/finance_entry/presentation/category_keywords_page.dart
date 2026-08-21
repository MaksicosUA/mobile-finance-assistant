import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/category_keywords_controller.dart';
import '../domain/finance_entry_result.dart';

/// The words that lead to one category (ADR 0020 step 3).
///
/// A name is what reports show; these are what a written sentence is matched
/// against. Keeping them apart is what lets a category stay called
/// "Автомобиль" while "заправил", "машина" and "car" all reach it.
class CategoryKeywordsPage extends ConsumerStatefulWidget {
  const CategoryKeywordsPage({
    required this.categoryId,
    required this.categoryName,
    required this.onSignInRequested,
    super.key,
  });

  final String categoryId;
  final String categoryName;
  final Future<void> Function() onSignInRequested;

  @override
  ConsumerState<CategoryKeywordsPage> createState() =>
      _CategoryKeywordsPageState();
}

class _CategoryKeywordsPageState extends ConsumerState<CategoryKeywordsPage> {
  final _controller = TextEditingController();
  bool _signInRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(categoryKeywordsControllerProvider.notifier)
          .load(widget.categoryId);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(categoryKeywordsControllerProvider);

    if (state is CategoryKeywordsAuthenticationRequired && !_signInRequested) {
      _signInRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await widget.onSignInRequested();
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.categoryKeywordsTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.screenMaxWidth,
            ),
            child: switch (state) {
              CategoryKeywordsLoading() ||
              CategoryKeywordsAuthenticationRequired() => const Center(
                key: Key('category-keywords-loading'),
                child: CircularProgressIndicator.adaptive(),
              ),
              CategoryKeywordsFailure() => Center(
                key: const Key('category-keywords-failure'),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.categoryKeywordsLoadError,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        key: const Key('category-keywords-retry'),
                        onPressed: () => ref
                            .read(categoryKeywordsControllerProvider.notifier)
                            .load(widget.categoryId),
                        child: Text(l10n.retryAction),
                      ),
                    ],
                  ),
                ),
              ),
              CategoryKeywordsReady() => _ready(context, l10n, state),
            },
          ),
        ),
      ),
    );
  }

  Widget _ready(
    BuildContext context,
    AppLocalizations l10n,
    CategoryKeywordsReady state,
  ) {
    final theme = Theme.of(context);
    final notifier = ref.read(categoryKeywordsControllerProvider.notifier);
    return ListView(
      key: const Key('category-keywords-page'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(widget.categoryName, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.categoryKeywordsDescription,
          style: theme.textTheme.bodySmall,
        ),
        if (state.failure case final failure?) ...[
          const SizedBox(height: AppSpacing.md),
          _Message(text: _failureText(l10n, failure)),
        ],
        const SizedBox(height: AppSpacing.md),
        if (state.keywords.isEmpty)
          Text(
            l10n.categoryKeywordsEmpty,
            key: const Key('category-keywords-empty'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final keyword in state.keywords)
                InputChip(
                  key: Key('category-keyword-$keyword'),
                  label: Text(keyword),
                  isEnabled: !state.isSubmitting,
                  // An explicit icon so the remove action has a stable handle
                  // instead of depending on the theme's default glyph.
                  deleteIcon: Icon(
                    Icons.close_rounded,
                    key: Key('category-keyword-remove-$keyword'),
                    size: 18,
                  ),
                  onDeleted: state.isSubmitting
                      ? null
                      : () => notifier.remove(keyword),
                  deleteButtonTooltipMessage: l10n.categoryKeywordsRemove(
                    keyword,
                  ),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          key: const Key('category-keyword-field'),
          controller: _controller,
          enabled: !state.isSubmitting,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 40,
          inputFormatters: [LengthLimitingTextInputFormatter(40)],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(notifier),
          decoration: InputDecoration(
            labelText: l10n.categoryKeywordsField,
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          key: const Key('category-keyword-add'),
          onPressed: state.isSubmitting ? null : () => _submit(notifier),
          child: Text(l10n.categoryKeywordsAdd),
        ),
      ],
    );
  }

  void _submit(CategoryKeywordsController notifier) {
    final word = _controller.text;
    if (word.trim().isEmpty) return;
    _controller.clear();
    notifier.add(word);
  }

  String _failureText(AppLocalizations l10n, FinanceEntryFailure failure) {
    if (failure.code == FinanceEntryErrorCode.categoryKeywordTaken) {
      return l10n.categoryKeywordsTaken;
    }
    if (failure.code == FinanceEntryErrorCode.categoryArchived) {
      return l10n.categoryKeywordsArchived;
    }
    if (failure.kind == FinanceEntryFailureKind.invalidInput) {
      return l10n.categoryKeywordsInvalid;
    }
    return l10n.categoryKeywordsSaveError;
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('category-keywords-message'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.appColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
