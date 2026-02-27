import 'package:flutter/material.dart';

/// Searchable location filter for the analytics dashboard.
///
/// Uses [Autocomplete] so users can type to search cities rather than
/// scrolling through a dropdown.
class LocationFilter extends StatefulWidget {
  final List<String> cities;
  final String? selectedCity;
  final ValueChanged<String?> onChanged;

  const LocationFilter({
    super.key,
    required this.cities,
    required this.selectedCity,
    required this.onChanged,
  });

  @override
  State<LocationFilter> createState() => _LocationFilterState();
}

class _LocationFilterState extends State<LocationFilter> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.selectedCity ?? '');
  }

  @override
  void didUpdateWidget(LocationFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCity != widget.selectedCity) {
      _controller.text = widget.selectedCity ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<String>(
          textEditingController: _controller,
          focusNode: FocusNode(),
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.toLowerCase().trim();
            if (query.isEmpty) return widget.cities;
            return widget.cities.where(
              (city) => city.toLowerCase().contains(query),
            );
          },
          onSelected: (city) {
            widget.onChanged(city);
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: 'Search city or "All Locations"',
                prefixIcon: Icon(
                  Icons.location_on_outlined,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                suffixIcon: widget.selectedCity != null
                    ? IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          _controller.clear();
                          widget.onChanged(null);
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              style: theme.textTheme.bodyMedium,
              onSubmitted: (_) => onSubmitted(),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 240,
                    maxWidth: constraints.maxWidth,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length + 1, // +1 for "All Locations"
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ListTile(
                          leading: Icon(
                            Icons.public,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          title: Text(
                            'All Locations',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: widget.selectedCity == null
                                  ? FontWeight.w600
                                  : null,
                              color: widget.selectedCity == null
                                  ? colorScheme.primary
                                  : null,
                            ),
                          ),
                          dense: true,
                          onTap: () {
                            _controller.clear();
                            widget.onChanged(null);
                            FocusScope.of(context).unfocus();
                          },
                        );
                      }
                      final city = options.elementAt(index - 1);
                      final isSelected = city == widget.selectedCity;
                      return ListTile(
                        leading: Icon(
                          Icons.location_city,
                          size: 20,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          city,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isSelected ? FontWeight.w600 : null,
                            color: isSelected ? colorScheme.primary : null,
                          ),
                        ),
                        dense: true,
                        onTap: () => onSelected(city),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
