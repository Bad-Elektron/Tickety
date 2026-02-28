import 'package:flutter/material.dart';

import '../models/event_category.dart';
import '../models/event_tag.dart';
import 'event_filter_bottom_sheet.dart';

/// Filter bar for events with inline search, active filter pills, and filter sheet.
class EventFilterChips extends StatefulWidget {
  const EventFilterChips({
    super.key,
    required this.selectedCategories,
    required this.selectedCity,
    required this.selectedTags,
    required this.availableCities,
    required this.onCategoriesChanged,
    required this.onCityChanged,
    required this.onTagsChanged,
    required this.isSearching,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onSearchToggled,
  });

  final Set<EventCategory> selectedCategories;
  final String? selectedCity;
  final Set<String> selectedTags;
  final List<String> availableCities;
  final ValueChanged<Set<EventCategory>> onCategoriesChanged;
  final ValueChanged<String?> onCityChanged;
  final ValueChanged<Set<String>> onTagsChanged;
  final bool isSearching;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchToggled;

  @override
  State<EventFilterChips> createState() => _EventFilterChipsState();
}

class _EventFilterChipsState extends State<EventFilterChips>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _expandAnimation;

  bool get _hasActiveFilters =>
      widget.selectedCity != null ||
      widget.selectedCategories.isNotEmpty ||
      widget.selectedTags.isNotEmpty;

  int get _activeFilterCount =>
      widget.selectedCategories.length +
      (widget.selectedCity != null ? 1 : 0) +
      widget.selectedTags.length;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    if (widget.isSearching) _animController.value = 1.0;
  }

  @override
  void didUpdateWidget(EventFilterChips old) {
    super.didUpdateWidget(old);
    if (widget.isSearching && !old.isSearching) {
      _animController.forward();
    } else if (!widget.isSearching && old.isSearching) {
      _animController.reverse();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EventFilterBottomSheet(
        selectedCategories: widget.selectedCategories,
        selectedCity: widget.selectedCity,
        selectedTags: widget.selectedTags,
        availableCities: widget.availableCities,
        onCategoriesChanged: widget.onCategoriesChanged,
        onCityChanged: widget.onCityChanged,
        onTagsChanged: widget.onTagsChanged,
      ),
    );
  }

  void _clearAllFilters() {
    widget.onCategoriesChanged({});
    widget.onCityChanged(null);
    widget.onTagsChanged({});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top row: Filter button + search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              // Filter button
              GestureDetector(
                onTap: _openFilterSheet,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _hasActiveFilters
                        ? colorScheme.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _hasActiveFilters
                          ? colorScheme.primary.withValues(alpha: 0.3)
                          : colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 16,
                        color: _hasActiveFilters
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Filters',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: _hasActiveFilters
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          fontWeight: _hasActiveFilters
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      if (_hasActiveFilters) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$_activeFilterCount',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Search area
              Expanded(
                child: widget.isSearching
                    ? FadeTransition(
                        opacity: _expandAnimation,
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: widget.searchController,
                                  focusNode: widget.searchFocusNode,
                                  onChanged: widget.onSearchChanged,
                                  autofocus: true,
                                  style: theme.textTheme.bodyMedium,
                                  decoration: InputDecoration(
                                    hintText: 'Search events...',
                                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: widget.onSearchToggled,
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // Search icon — only when collapsed
              if (!widget.isSearching)
                GestureDetector(
                  onTap: widget.onSearchToggled,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Active filter pills row
        if (_hasActiveFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // Category pills
                ...widget.selectedCategories.map((cat) => _FilterPill(
                  label: cat.label,
                  icon: cat.icon,
                  onRemove: () {
                    final updated = Set<EventCategory>.from(widget.selectedCategories)
                      ..remove(cat);
                    widget.onCategoriesChanged(updated);
                  },
                )),
                // City pill
                if (widget.selectedCity != null)
                  _FilterPill(
                    label: widget.selectedCity!,
                    icon: Icons.location_on_outlined,
                    onRemove: () => widget.onCityChanged(null),
                  ),
                // Tag pills
                ...widget.selectedTags.map((tagId) {
                  final tag = PredefinedTags.all
                      .where((t) => t.id == tagId)
                      .firstOrNull;
                  return _FilterPill(
                    label: tag?.label ?? tagId,
                    icon: tag?.icon ?? Icons.label_outline,
                    color: tag?.color,
                    onRemove: () {
                      final updated = Set<String>.from(widget.selectedTags)
                        ..remove(tagId);
                      widget.onTagsChanged(updated);
                    },
                  );
                }),
                // Clear all
                GestureDetector(
                  onTap: _clearAllFilters,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Clear all',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Small removable pill for an active filter.
class _FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final VoidCallback onRemove;

  const _FilterPill({
    required this.label,
    required this.icon,
    this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pillColor = color ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.only(left: 8, right: 2, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pillColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: pillColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: pillColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 12, color: pillColor.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }
}
