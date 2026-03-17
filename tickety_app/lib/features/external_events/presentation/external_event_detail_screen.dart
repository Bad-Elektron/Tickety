import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/external_event.dart';

class ExternalEventDetailScreen extends StatelessWidget {
  final ExternalEvent event;

  const ExternalEventDetailScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero image
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: event.imageUrl != null
                  ? Image.network(
                      event.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colorScheme.primary, colorScheme.tertiary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [colorScheme.primary, colorScheme.tertiary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _sourceColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'via ${event.sourceLabel}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _sourceColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Title
                  Text(
                    event.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Date
                  _InfoRow(
                    icon: Icons.calendar_today,
                    label: _formatDate(event.startDate),
                    color: colorScheme.primary,
                  ),
                  if (event.venueName != null) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: event.venueName!,
                      sublabel: event.venueAddress,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                  if (event.genre != null) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.category_outlined,
                      label: '${event.category ?? 'Event'} — ${event.genre}',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                  if (event.formattedPrice.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.sell_outlined,
                      label: event.formattedPrice,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],

                  // Description
                  if (event.description != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'About',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      event.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],

                  const SizedBox(height: 100), // Space for bottom button
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => _openTicketUrl(context),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text('Get Tickets on ${event.sourceLabel}'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Color get _sourceColor {
    switch (event.source) {
      case 'ticketmaster':
        return const Color(0xFF026CDF); // Ticketmaster blue
      case 'seatgeek':
        return const Color(0xFFF05537); // SeatGeek orange
      default:
        return const Color(0xFF6366F1);
    }
  }

  String _formatDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    final min = date.minute.toString().padLeft(2, '0');
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day} at $hour:$min $ampm';
  }

  Future<void> _openTicketUrl(BuildContext context) async {
    final uri = Uri.parse(event.ticketUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final Color color;

  const _InfoRow({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              if (sublabel != null)
                Text(sublabel!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
