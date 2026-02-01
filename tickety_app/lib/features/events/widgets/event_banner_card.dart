import 'package:flutter/material.dart';

import '../../../shared/widgets/widgets.dart';
import '../models/event_model.dart';

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
          const SizedBox(height: 16),
          _buildFooter(context),
        ],
      ),
    );
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
        if (event.location != null) ...[
          const Icon(Icons.location_on_outlined, size: 16, color: Color(0xCCFFFFFF)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              event.location!,
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
