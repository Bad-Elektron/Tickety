import 'package:flutter/material.dart';

import '../../../shared/widgets/widgets.dart';
import '../models/event_model.dart';
import '../models/event_series.dart';

/// A card displaying an event with a gradient background and text overlay.
class EventBannerCard extends StatelessWidget {
  final EventModel event;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final EdgeInsets contentPadding;

  const EventBannerCard({
    super.key,
    required this.event,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.contentPadding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.hardEdge, // hardEdge is faster than antiAlias
        elevation: 2, // Reduced elevation = simpler shadow
        shadowColor: const Color(0x40000000),
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background gradient
              _buildBackground(),
              // Dark overlay for text readability
              _buildGradientOverlay(),
              // Content
              _buildContent(context),
              // Category badge
              if (event.category != null) _buildCategoryBadge(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    final config = event.getNoiseConfig();
    return GradientBackground(colors: config.colors);
  }

  Widget _buildGradientOverlay() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Color(0x4D000000),
            Color(0xCC000000),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          _buildDateChip(context),
          const SizedBox(height: 12),
          Text(
            event.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            event.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xE6FFFFFF),
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (event.organizerName != null || event.organizerHandle != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'by ${event.organizerHandle ?? event.organizerName ?? ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xAAFFFFFF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (event.organizerVerified) ...[
                  const SizedBox(width: 4),
                  const VerifiedBadge(size: 14),
                ],
              ],
            ),
          ],
          const SizedBox(height: 8),
          _buildTagChips(context),
          const SizedBox(height: 12),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildTagChips(BuildContext context) {
    final badges = event.autoBadges;
    final tags = event.eventTags;
    if (badges.isEmpty && tags.isEmpty) return const SizedBox.shrink();

    final chips = <Widget>[];

    // Auto-badges first with distinct styling
    for (final badge in badges) {
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: badge.color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(badge.icon, size: 12, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              badge.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ));
    }

    // Virtual/Hybrid badge
    if (event.hasVirtualComponent) {
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.cyan.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam, size: 12, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              event.isVirtual ? 'Virtual' : 'Hybrid',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ));
    }

    // Recurring badge
    if (event.isPartOfSeries && event.recurrenceType != null) {
      final recurrence = RecurrenceType.fromString(event.recurrenceType);
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.repeat, size: 12, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              recurrence?.shortLabel ?? 'Recurring',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ));
    }

    // Regular tags (up to 3 total including badges)
    final maxRegularTags = 3 - badges.length - (event.isPartOfSeries ? 1 : 0) - (event.hasVirtualComponent ? 1 : 0);
    final visibleTags = tags.take(maxRegularTags);
    for (final tag in visibleTags) {
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tag.icon != null) ...[
              Icon(tag.icon, size: 12, color: Colors.white),
              const SizedBox(width: 3),
            ],
            Text(
              tag.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ));
    }

    // "+N more" chip if overflow
    final remaining = tags.length - maxRegularTags;
    if (remaining > 0) {
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x22FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '+$remaining',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: const Color(0xAAFFFFFF),
            fontSize: 10,
          ),
        ),
      ));
    }

    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _buildDateChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x4DFFFFFF)),
      ),
      child: Text(
        _formatDate(event.date),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      children: [
        if (event.getDisplayLocation(hasTicket: false) != null) ...[
          Icon(
            event.hideLocation ? Icons.lock_outlined : Icons.location_on_outlined,
            size: 16,
            color: const Color(0xCCFFFFFF),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              event.getDisplayLocation(hasTicket: false)!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xCCFFFFFF),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: event.isFree ? const Color(0xE64CAF50) : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            event.formattedPrice,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: event.isFree ? Colors.white : const Color(0xDD000000),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBadge(BuildContext context) {
    return Positioned(
      top: contentPadding.top,
      right: contentPadding.right,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x80000000),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          event.category!,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    final difference = eventDay.difference(today).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    if (difference == -1) return 'Yesterday';
    if (difference < -1) {
      return 'Ended · ${months[date.month - 1]} ${date.day}';
    }
    if (difference < 7) return 'In $difference days';

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
