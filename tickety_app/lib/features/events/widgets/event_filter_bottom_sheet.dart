import 'package:flutter/material.dart';

import '../../../core/localization/localization.dart';
import '../models/event_category.dart';
import '../models/event_tag.dart';
import 'city_selector.dart';

/// Modal bottom sheet for advanced event filtering.
///
/// Includes category selection, city selection with search,
/// tag browsing (Category + Vibe groups), and Apply/Clear All buttons.
class EventFilterBottomSheet extends StatefulWidget {
  const EventFilterBottomSheet({
    super.key,
    required this.selectedCategories,
    required this.selectedCity,
    required this.selectedTags,
    required this.availableCities,
    required this.onCategoriesChanged,
    required this.onCityChanged,
    required this.onTagsChanged,
  });

  final Set<EventCategory> selectedCategories;
  final String? selectedCity;
  final Set<String> selectedTags;
  final List<String> availableCities;
  final ValueChanged<Set<EventCategory>> onCategoriesChanged;
  final ValueChanged<String?> onCityChanged;
  final ValueChanged<Set<String>> onTagsChanged;

  @override
  State<EventFilterBottomSheet> createState() => _EventFilterBottomSheetState();
}

class _EventFilterBottomSheetState extends State<EventFilterBottomSheet> {
  late Set<EventCategory> _selectedCategories;
  late String? _selectedCity;
  late Set<String> _selectedTags;

  @override
  void initState() {
    super.initState();
    _selectedCategories = Set.from(widget.selectedCategories);
    _selectedCity = widget.selectedCity;
    _selectedTags = Set.from(widget.selectedTags);
  }

  bool get _hasAnyFilter =>
      _selectedCategories.isNotEmpty ||
      _selectedCity != null ||
      _selectedTags.isNotEmpty;

  int get _activeCount =>
      _selectedCategories.length +
      (_selectedCity != null ? 1 : 0) +
      _selectedTags.length;

  void _handleCategoryTap(EventCategory category) {
    setState(() {
      if (_selectedCategories.contains(category)) {
        _selectedCategories.remove(category);
      } else {
        _selectedCategories.add(category);
      }
    });
  }

  void _handleTagTap(EventTag tag) {
    setState(() {
      if (_selectedTags.contains(tag.id)) {
        _selectedTags.remove(tag.id);
      } else {
        _selectedTags.add(tag.id);
      }
    });
  }

  void _handleClearAll() {
    setState(() {
      _selectedCategories.clear();
      _selectedCity = null;
      _selectedTags.clear();
    });
  }

  void _handleApply() {
    widget.onCategoriesChanged(_selectedCategories);
    widget.onCityChanged(_selectedCity);
    widget.onTagsChanged(_selectedTags);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
            child: Row(
              children: [
                Text(
                  L.tr('Filters'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_hasAnyFilter) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_activeCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (_hasAnyFilter)
                  TextButton(
                    onPressed: _handleClearAll,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(L.tr('Clear all')),
                  ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 16 + bottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Categories ──
                  _SectionHeader(
                    title: L.tr('Categories'),
                    icon: Icons.grid_view_rounded,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: EventCategory.values.map((category) {
                      final selected =
                          _selectedCategories.contains(category);
                      return _FilterChip(
                        label: category.label,
                        icon: category.icon,
                        selected: selected,
                        onTap: () => _handleCategoryTap(category),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 28),

                  // ── Location ──
                  _SectionHeader(
                    title: L.tr('Location'),
                    icon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 12),
                  CitySelector(
                    cities: widget.availableCities,
                    selectedCity: _selectedCity,
                    onCitySelected: (city) {
                      setState(() => _selectedCity = city);
                    },
                  ),

                  const SizedBox(height: 28),

                  // ── Tags: Category ──
                  _SectionHeader(
                    title: L.tr('Tags'),
                    icon: Icons.label_outlined,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    L.tr('Category'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: PredefinedTags.categories.map((tag) {
                      final selected = _selectedTags.contains(tag.id);
                      return _FilterChip(
                        label: tag.label,
                        icon: tag.icon,
                        color: tag.color,
                        selected: selected,
                        onTap: () => _handleTagTap(tag),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // ── Tags: Vibe ──
                  Text(
                    L.tr('Vibe'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: PredefinedTags.vibes.map((tag) {
                      final selected = _selectedTags.contains(tag.id);
                      return _FilterChip(
                        label: tag.label,
                        icon: tag.icon,
                        color: tag.color,
                        selected: selected,
                        onTap: () => _handleTagTap(tag),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Apply button
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 12 + bottomPadding),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _handleApply,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _hasAnyFilter
                        ? '${L.tr('Apply Filters')} ($_activeCount)'
                        : L.tr('Apply Filters'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header with icon and title.
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Compact filter chip with optional color accent.
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.icon,
    this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chipColor = color ?? colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? chipColor.withValues(alpha: 0.15)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? chipColor.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? chipColor : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? chipColor : colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check_rounded,
                size: 14,
                color: chipColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
