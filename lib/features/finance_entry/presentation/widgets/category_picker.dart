import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/finance_entry_models.dart';

/// Localized label for one category (ADR 0020).
///
/// A seeded row carries a stable key, so its label follows the app language.
/// A renamed row carries none and shows the name the user chose — translating
/// that would contradict their choice.
String categoryLabel(AppLocalizations l10n, FinanceCategory category) {
  return switch (category.systemKey) {
    'groceries' => l10n.categorySeedGroceries,
    'eating_out' => l10n.categorySeedEatingOut,
    'transport' => l10n.categorySeedTransport,
    'housing' => l10n.categorySeedHousing,
    'utilities' => l10n.categorySeedUtilities,
    'health' => l10n.categorySeedHealth,
    'clothing' => l10n.categorySeedClothing,
    'entertainment' => l10n.categorySeedEntertainment,
    'education' => l10n.categorySeedEducation,
    'gifts_out' => l10n.categorySeedGiftsOut,
    'other_expense' => l10n.categorySeedOtherExpense,
    'salary' => l10n.categorySeedSalary,
    'freelance' => l10n.categorySeedFreelance,
    'gifts_in' => l10n.categorySeedGiftsIn,
    'interest' => l10n.categorySeedInterest,
    'other_income' => l10n.categorySeedOtherIncome,
    // An unknown key means the server seeded something this build predates.
    // Showing the stored name is better than showing the raw key.
    _ => category.name,
  };
}

/// The value the picker currently holds.
///
/// Free text stays reachable so a missing catalogue, or a category nobody has
/// created yet, never blocks recording money.
sealed class CategoryChoice {
  const CategoryChoice();
}

final class CategoryUnset extends CategoryChoice {
  const CategoryUnset();
}

final class CategoryFromCatalogue extends CategoryChoice {
  const CategoryFromCatalogue(this.category);

  final FinanceCategory category;
}

final class CategoryFreeText extends CategoryChoice {
  const CategoryFreeText();
}

/// Picks a category for one direction, falling back to free text.
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    required this.categories,
    required this.choice,
    required this.freeTextController,
    required this.enabled,
    required this.onChanged,
    this.catalogueUnavailable = false,
    super.key,
  });

  final List<FinanceCategory> categories;
  final CategoryChoice choice;
  final TextEditingController freeTextController;
  final bool enabled;
  final ValueChanged<CategoryChoice> onChanged;

  /// The catalogue could not be read. The field degrades to plain text rather
  /// than offering an empty list that looks like "you have no categories".
  final bool catalogueUnavailable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (catalogueUnavailable) {
      return _freeTextField(
        l10n,
        helper: l10n.categoryPickerUnavailable,
        key: const Key('operation-category'),
      );
    }

    final selectedId = switch (choice) {
      CategoryFromCatalogue(:final category) => category.categoryId,
      CategoryFreeText() => _freeTextValue,
      CategoryUnset() => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          key: const Key('operation-category-picker'),
          initialValue: selectedId,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.categoryField),
          onChanged: enabled ? (value) => onChanged(_choiceFor(value)) : null,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(l10n.categoryPickerNone),
            ),
            for (final category in categories)
              DropdownMenuItem<String?>(
                value: category.categoryId,
                child: Text(
                  categoryLabel(l10n, category),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            DropdownMenuItem<String?>(
              value: _freeTextValue,
              child: Text(l10n.categoryPickerOther),
            ),
          ],
        ),
        if (choice is CategoryFreeText) ...[
          const SizedBox(height: 8),
          _freeTextField(
            l10n,
            helper: null,
            key: const Key('operation-category'),
          ),
        ],
      ],
    );
  }

  Widget _freeTextField(
    AppLocalizations l10n, {
    required String? helper,
    required Key key,
  }) {
    return TextFormField(
      key: key,
      controller: freeTextController,
      enabled: enabled,
      maxLength: 100,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: catalogueUnavailable
            ? l10n.categoryField
            : l10n.categoryPickerOtherLabel,
        helperText: helper,
        helperMaxLines: 2,
        counterText: '',
      ),
    );
  }

  CategoryChoice _choiceFor(String? value) {
    if (value == null) return const CategoryUnset();
    if (value == _freeTextValue) return const CategoryFreeText();
    for (final category in categories) {
      if (category.categoryId == value) return CategoryFromCatalogue(category);
    }
    return const CategoryUnset();
  }
}

// Not a UUID, so it can never collide with a real category identifier.
const String _freeTextValue = 'free-text';
