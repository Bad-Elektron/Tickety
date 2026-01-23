import 'package:flutter/material.dart';

import '../../../shared/widgets/widgets.dart';
import '../models/event_category.dart';
import 'event_filter_bottom_sheet.dart';

/// Horizontal scrollable filter row for event categories.
///
/// Features an "All" chip to clear selection, category chips for multi-select
/// filtering, and a filter icon button to open the advanced filter bottom sheet.
class EventFilterChips extends StatelessWidget {
  const EventFilterChips({
    super.key,
    required this.selectedCategories,
    required this.selectedCity,
    required this.availableCities,
    required this.onCategoriesChanged,
    required this.onCityChanged,
  });

  /// Currently selected categories (empty means all).
  final Set<EventCategory> selectedCategories;

  /// Currently selected city (null means any location).
  final String? selectedCity;

  /// List of available cities for filtering.
  final List<String> availableCities;

  /// Callback when category selection changes.
  final ValueChanged<Set<EventCategory>> onCategoriesChanged;

  /// Callback when city selection changes.
  final ValueChanged<String?> onCityChanged;

  bool get _hasLocationFilter => selectedCity != null;

  void _handleAllTap() {
    onCategoriesChanged({});
  }

  void _handleCategoryTap(EventCategory category) {
    final newSelection = Set<EventCategory>.from(selectedCategories);
    if (newSelection.contains(category)) {
      newSelection.remove(category);
    } else {
      newSelection.add(category);
    }
    onCategoriesChanged(newSelection);
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EventFilterBottomSheet(
        selectedCategories: selectedCategories,
        selectedCity: selectedCity,
        availableCities: availableCities,
        onCategoriesChanged: onCategoriesChanged,
        onCityChanged: onCityChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return RepaintBoundary(
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // "All" chip
                  AppFilterChip(
                    label: 'All',
                    selected: selectedCategories.isEmpty,
                    onSelected: (_) => _handleAllTap(),
                  ),
                  const SizedBox(width: 8),
                  // Category chips
                  ...EventCategory.values.map((category) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      label: category.label,
                      icon: category.icon,
                      selected: selectedCategories.contains(category),
                      onSelected: (_) => _handleCategoryTap(category),
                    ),
                  )),
                ],
              ),
            ),
            // Filter button with badge
            Container(
              margin: const EdgeInsets.only(right: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openFilterSheet(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _hasLocationFilter
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _hasLocationFilter
                            ? colorScheme.primary
                            : colorScheme.outline.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.tune,
                          size: 20,
                          color: _hasLocationFilter
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        if (_hasLocationFilter)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.surface,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
