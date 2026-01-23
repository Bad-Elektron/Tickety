import 'package:flutter/material.dart';

/// City selection component with search functionality.
///
/// Features a search field to filter cities, a list of available cities
/// with checkmarks for selection, and an "Any Location" option to clear.
class CitySelector extends StatefulWidget {
  const CitySelector({
    super.key,
    required this.cities,
    required this.selectedCity,
    required this.onCitySelected,
  });

  /// List of available cities to choose from.
  final List<String> cities;

  /// Currently selected city (null means any location).
  final String? selectedCity;

  /// Callback when a city is selected or cleared.
  final ValueChanged<String?> onCitySelected;

  @override
  State<CitySelector> createState() => _CitySelectorState();
}

class _CitySelectorState extends State<CitySelector> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filteredCities {
    if (_searchQuery.isEmpty) return widget.cities;
    final query = _searchQuery.toLowerCase();
    return widget.cities
        .where((city) => city.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search cities...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
        const SizedBox(height: 12),

        // City list
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView(
            shrinkWrap: true,
            children: [
              // "Any Location" option
              _CityTile(
                city: 'Any Location',
                isSelected: widget.selectedCity == null,
                onTap: () => widget.onCitySelected(null),
                icon: Icons.public,
              ),
              const Divider(height: 1),
              // Filtered cities
              ..._filteredCities.map((city) => _CityTile(
                city: city,
                isSelected: widget.selectedCity == city,
                onTap: () => widget.onCitySelected(city),
              )),
              if (_filteredCities.isEmpty && _searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No cities found',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CityTile extends StatelessWidget {
  const _CityTile({
    required this.city,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  final String city;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      dense: true,
      leading: Icon(
        icon ?? Icons.location_city,
        size: 20,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        city,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: colorScheme.primary,
              size: 20,
            )
          : null,
      onTap: onTap,
    );
  }
}
