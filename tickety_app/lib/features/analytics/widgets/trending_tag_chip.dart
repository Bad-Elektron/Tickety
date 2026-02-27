import 'package:flutter/material.dart';

import '../../events/models/event_tag.dart';
import '../models/trending_tag.dart';

/// A chip displaying a trending tag with its trend direction and event count.
class TrendingTagChip extends StatelessWidget {
  final TrendingTag tag;
  final bool isSelected;
  final VoidCallback onTap;

  const TrendingTagChip({
    super.key,
    required this.tag,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Try to get the predefined tag color
    final predefined = PredefinedTags.all.where((t) => t.id == tag.tagId);
    final tagColor = predefined.isNotEmpty
        ? predefined.first.color ?? colorScheme.primary
        : colorScheme.primary;

    return Material(
      color: isSelected
          ? tagColor.withValues(alpha: 0.2)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: tagColor.withValues(alpha: 0.5), width: 1.5)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tag icon if available
              if (predefined.isNotEmpty && predefined.first.icon != null) ...[
                Icon(
                  predefined.first.icon,
                  size: 16,
                  color: tagColor,
                ),
                const SizedBox(width: 6),
              ],
              // Tag label
              Text(
                tag.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? tagColor : colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              // Trend indicator
              Icon(
                tag.isTrendingUp
                    ? Icons.trending_up
                    : tag.isTrendingDown
                        ? Icons.trending_down
                        : Icons.trending_flat,
                size: 16,
                color: tag.isTrendingUp
                    ? Colors.green
                    : tag.isTrendingDown
                        ? Colors.red
                        : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              // Event count
              Text(
                '${tag.totalEvents30d}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
