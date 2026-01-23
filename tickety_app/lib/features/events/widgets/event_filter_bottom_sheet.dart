import 'package:flutter/material.dart';

import '../../../shared/widgets/widgets.dart';
import '../models/event_category.dart';
import 'city_selector.dart';

/// Modal bottom sheet for advanced event filtering.
///
/// Includes category selection (synced with main filter chips),
/// city selection with search, and Apply/Clear All buttons.
class EventFilterBottomSheet extends StatefulWidget {
  const EventFilterBottomSheet({
    super.key,
    required this.selectedCategories,
    required this.selectedCity,
    required this.availableCities,
    required this.onCategoriesChanged,
    required this.onCityChanged,
  });

  /// Initially selected categories.
  final Set<EventCategory> selectedCategories;

  /// Initially selected city.
  final String? selectedCity;

  /// List of available cities.
  final List<String> availableCities;

  /// Callback when categories change.
  final ValueChanged<Set<EventCategory>> onCategoriesChanged;

  /// Callback when city changes.
  final ValueChanged<String?> onCityChanged;

  @override
  State<EventFilterBottomSheet> createState() => _EventFilterBottomSheetState();
}

class _EventFilterBottomSheetState extends State<EventFilterBottomSheet> {
  late Set<EventCategory> _selectedCategories;
  late String? _selectedCity;

  @override
  void initState() {
    super.initState();
    _selectedCategories = Set.from(widget.selectedCategories);
    _selectedCity = widget.selectedCity;
  }

  bool get _hasAnyFilter =>
      _selectedCategories.isNotEmpty || _selectedCity != null;

  void _handleCategoryTap(EventCategory category) {
    setState(() {
      if (_selectedCategories.contains(category)) {
        _selectedCategories.remove(category);
      } else {
        _selectedCategories.add(category);
      }
    });
  }

  void _handleClearAll() {
    setState(() {
      _selectedCategories.clear();
      _selectedCity = null;
    });
  }

  void _handleApply() {
    widget.onCategoriesChanged(_selectedCategories);
    widget.onCityChanged(_selectedCity);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_hasAnyFilter)
                  TextButton(
                    onPressed: _handleClearAll,
                    child: const Text('Clear All'),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Categories section
                  Text(
                    'Categories',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: EventCategory.values.map((category) {
                      return AppFilterChip(
                        label: category.label,
                        icon: category.icon,
                        selected: _selectedCategories.contains(category),
                        onSelected: (_) => _handleCategoryTap(category),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  // Location section
                  Text(
                    'Location',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CitySelector(
                    cities: widget.availableCities,
                    selectedCity: _selectedCity,
                    onCitySelected: (city) {
                      setState(() => _selectedCity = city);
                    },
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
              padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPadding),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _handleApply,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Apply Filters'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
