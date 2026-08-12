import 'package:flutter/foundation.dart';

import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';

/// States of the category management screen (ADR 0020, step 2b).
///
/// A category is a label, never money, so there is no review step here: none
/// of these writes can change a balance, and an explicit confirmation would
/// protect nothing.
sealed class CategoryManagementState {
  const CategoryManagementState();
}

final class CategoryManagementLoading extends CategoryManagementState {
  const CategoryManagementLoading();
}

@immutable
final class CategoryManagementReady extends CategoryManagementState {
  CategoryManagementReady({
    required this.direction,
    List<ManagedFinanceCategory> categories = const [],
    this.newName = '',
    this.editedName = '',
    this.isCreating = false,
    this.editingCategoryId,
    this.busyCategoryId,
    this.isSubmitting = false,
    this.showHidden = false,
    this.failure,
  }) : categories = List<ManagedFinanceCategory>.unmodifiable(categories);

  /// Expense and income catalogues are separate: an expense must never be
  /// offered an income category, so they are never shown mixed.
  final FinanceOperationType direction;
  final List<ManagedFinanceCategory> categories;

  /// The name typed into the create field.
  final String newName;

  /// The name typed into the rename field of [editingCategoryId].
  final String editedName;
  final bool isCreating;
  final String? editingCategoryId;

  /// The category a hide/restore is in flight for, so only that row shows
  /// progress instead of the whole screen.
  final String? busyCategoryId;
  final bool isSubmitting;

  /// Hidden categories stay collapsed: they are a recovery list, not the
  /// working one.
  final bool showHidden;
  final FinanceEntryFailure? failure;

  List<ManagedFinanceCategory> get offered => [
    for (final category in categories)
      if (category.direction == direction && !category.isArchived) category,
  ];

  List<ManagedFinanceCategory> get hidden => [
    for (final category in categories)
      if (category.direction == direction && category.isArchived) category,
  ];

  CategoryManagementReady copyWith({
    FinanceOperationType? direction,
    List<ManagedFinanceCategory>? categories,
    String? newName,
    String? editedName,
    bool? isCreating,
    String? editingCategoryId,
    String? busyCategoryId,
    bool? isSubmitting,
    bool? showHidden,
    FinanceEntryFailure? failure,
    bool clearFailure = false,
    bool clearEditing = false,
    bool clearBusy = false,
  }) {
    return CategoryManagementReady(
      direction: direction ?? this.direction,
      categories: categories ?? this.categories,
      newName: newName ?? this.newName,
      editedName: editedName ?? this.editedName,
      isCreating: isCreating ?? this.isCreating,
      editingCategoryId: clearEditing
          ? null
          : (editingCategoryId ?? this.editingCategoryId),
      busyCategoryId: clearBusy
          ? null
          : (busyCategoryId ?? this.busyCategoryId),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      showHidden: showHidden ?? this.showHidden,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

final class CategoryManagementAuthenticationRequired
    extends CategoryManagementState {
  const CategoryManagementAuthenticationRequired();
}

@immutable
final class CategoryManagementFailure extends CategoryManagementState {
  const CategoryManagementFailure(this.failure);

  final FinanceEntryFailure failure;
}
