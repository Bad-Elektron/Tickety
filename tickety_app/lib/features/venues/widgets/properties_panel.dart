import 'package:flutter/material.dart';

import '../models/models.dart';

/// Context-sensitive properties panel for editing the selected element.
class PropertiesPanel extends StatelessWidget {
  final VenueLayout layout;
  final String? selectedId;
  final ValueChanged<VenueSection> onSectionUpdated;
  final ValueChanged<VenueElement> onElementUpdated;
  final VoidCallback onDelete;
  final VoidCallback onGenerateSeats;

  const PropertiesPanel({
    super.key,
    required this.layout,
    required this.selectedId,
    required this.onSectionUpdated,
    required this.onElementUpdated,
    required this.onDelete,
    required this.onGenerateSeats,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedId == null) return _buildEmpty(context);

    // Check sections
    final section = layout.sections.where((s) => s.id == selectedId).firstOrNull;
    if (section != null) return _buildSectionProps(context, section);

    // Check elements
    final element = layout.elements.where((e) => e.id == selectedId).firstOrNull;
    if (element != null) return _buildElementProps(context, element);

    return _buildEmpty(context);
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Select an element\nto edit properties',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionProps(BuildContext context, VenueSection section) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.dashboard_outlined, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text('Section', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: onDelete,
                color: colorScheme.error,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Name
          TextFormField(
            initialValue: section.name,
            decoration: const InputDecoration(
              labelText: 'Name',
              isDense: true,
            ),
            onChanged: (value) => onSectionUpdated(section.copyWith(name: value)),
          ),
          const SizedBox(height: 12),
          // Type
          DropdownButtonFormField<SectionType>(
            value: section.type,
            decoration: const InputDecoration(
              labelText: 'Type',
              isDense: true,
            ),
            items: SectionType.values.map((t) {
              return DropdownMenuItem(value: t, child: Text(t.label));
            }).toList(),
            onChanged: (value) {
              if (value != null) onSectionUpdated(section.copyWith(type: value));
            },
          ),
          const SizedBox(height: 12),
          // Pricing tier
          TextFormField(
            initialValue: section.pricingTier ?? '',
            decoration: const InputDecoration(
              labelText: 'Pricing Tier',
              hintText: 'e.g., VIP, General',
              isDense: true,
            ),
            onChanged: (value) => onSectionUpdated(
              section.copyWith(pricingTier: value.isEmpty ? null : value),
            ),
          ),
          const SizedBox(height: 12),
          // Capacity (for standing/table)
          if (section.type != SectionType.seated)
            TextFormField(
              initialValue: section.capacity.toString(),
              decoration: const InputDecoration(
                labelText: 'Capacity',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final cap = int.tryParse(value);
                if (cap != null) onSectionUpdated(section.copyWith(capacity: cap));
              },
            ),
          // Color picker
          const SizedBox(height: 12),
          Text('Color', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sectionColors.map((hex) {
              final isSelected = section.color.toUpperCase() == hex.toUpperCase();
              final color = _parseColor(hex);
              return GestureDetector(
                onTap: () => onSectionUpdated(section.copyWith(color: hex)),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1)]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
          // Generate seats button (for seated sections)
          if (section.type == SectionType.seated) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onGenerateSeats,
              icon: const Icon(Icons.grid_view, size: 18),
              label: Text(section.rows.isEmpty ? 'Generate Seats' : 'Regenerate Seats'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Info
          Text(
            'Total: ${section.seatCount} ${section.type == SectionType.standing ? 'capacity' : 'seats'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildElementProps(BuildContext context, VenueElement element) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.category_outlined, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text('Element', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: onDelete,
                color: colorScheme.error,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: element.label,
            decoration: const InputDecoration(
              labelText: 'Label',
              isDense: true,
            ),
            onChanged: (value) => onElementUpdated(element.copyWith(label: value)),
          ),
          const SizedBox(height: 12),
          // Width & Height
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: element.shape.width.round().toString(),
                  decoration: const InputDecoration(labelText: 'W', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final w = double.tryParse(v);
                    if (w != null) {
                      onElementUpdated(element.copyWith(
                        shape: element.shape.copyWith(width: w),
                      ));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: element.shape.height.round().toString(),
                  decoration: const InputDecoration(labelText: 'H', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final h = double.tryParse(v);
                    if (h != null) {
                      onElementUpdated(element.copyWith(
                        shape: element.shape.copyWith(height: h),
                      ));
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _sectionColors = [
    '#6366F1', '#EC4899', '#F59E0B', '#10B981',
    '#3B82F6', '#8B5CF6', '#EF4444', '#06B6D4',
  ];

  Color _parseColor(String hex) {
    final hexStr = hex.replaceFirst('#', '');
    if (hexStr.length == 6) {
      return Color(int.parse('FF$hexStr', radix: 16));
    }
    return const Color(0xFF6366F1);
  }
}
