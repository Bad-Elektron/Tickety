import 'package:flutter/material.dart';

import '../models/event_category.dart';
import 'event_filter_bottom_sheet.dart';

/// Filter bar for events with inline search and filter options.
class EventFilterChips extends StatefulWidget {
  const EventFilterChips({
    super.key,
    required this.selectedCategories,
    required this.selectedCity,
    required this.availableCities,
    required this.onCategoriesChanged,
    required this.onCityChanged,
    required this.isSearching,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onSearchToggled,
  });

  final Set<EventCategory> selectedCategories;
  final String? selectedCity;
  final List<String> availableCities;
  final ValueChanged<Set<EventCategory>> onCategoriesChanged;
  final ValueChanged<String?> onCityChanged;
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
      widget.selectedCity != null || widget.selectedCategories.isNotEmpty;

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
        availableCities: widget.availableCities,
        onCategoriesChanged: widget.onCategoriesChanged,
        onCityChanged: widget.onCityChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          // Filter — just icon + text, no container
          GestureDetector(
            onTap: _openFilterSheet,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: _hasActiveFilters
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Filters',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _hasActiveFilters
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      fontWeight: _hasActiveFilters
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  if (_hasActiveFilters) ...[
                    const SizedBox(width: 5),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Search area — right side
          Expanded(
            child: widget.isSearching
                ? FadeTransition(
                    opacity: _expandAnimation,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
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
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.35),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: widget.onSearchToggled,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
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
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
