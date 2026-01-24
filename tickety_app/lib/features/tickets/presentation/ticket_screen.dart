import 'package:flutter/material.dart';

import '../../../core/graphics/graphics.dart';
import '../../staff/models/ticket.dart';

/// Screen displaying details of a single ticket.
class TicketScreen extends StatelessWidget {
  const TicketScreen({super.key, required this.ticket});

  final Ticket ticket;

  // Helper getters to extract event data
  String get _eventTitle =>
      ticket.eventData?['title'] as String? ?? 'Unknown Event';

  String? get _eventSubtitle => ticket.eventData?['subtitle'] as String?;

  String? get _venue => ticket.eventData?['venue'] as String?;

  String? get _city => ticket.eventData?['city'] as String?;

  String? get _country => ticket.eventData?['country'] as String?;

  DateTime? get _eventDate {
    final dateStr = ticket.eventData?['date'] as String?;
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  int get _noiseSeed =>
      ticket.eventData?['noise_seed'] as int? ?? ticket.ticketNumber.hashCode;

  String? get _fullAddress {
    final parts = <String>[];
    if (_venue != null) parts.add(_venue!);
    if (_city != null) parts.add(_city!);
    if (_country != null) parts.add(_country!);
    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  void _openNavigation(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.navigation, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Navigate to ${_fullAddress ?? _venue ?? "venue"}'),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with gradient background
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _TicketHeader(noiseSeed: _noiseSeed),
            ),
          ),
          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event title and subtitle
                  Text(
                    _eventTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_eventSubtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _eventSubtitle!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Ticket number
                  _InfoCard(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Ticket Number',
                    value: ticket.ticketNumber,
                    trailing: _StatusBadge(ticket: ticket),
                  ),
                  const SizedBox(height: 12),

                  // Date and time
                  _InfoCard(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date',
                    value: _eventDate != null
                        ? _formatDate(_eventDate!)
                        : 'To be announced',
                  ),
                  const SizedBox(height: 12),

                  // Location with navigation
                  _InfoCard(
                    icon: Icons.location_on_outlined,
                    label: 'Location',
                    value: _venue ?? 'TBA',
                    subtitle: _city != null
                        ? '$_city${_country != null ? ", $_country" : ""}'
                        : null,
                    trailing: IconButton(
                      onPressed: () => _openNavigation(context),
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.primary,
                      ),
                      icon: const Icon(Icons.navigation_rounded, size: 20),
                      tooltip: 'Get directions',
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Purchase info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Purchase Details',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DetailRow(
                          label: 'Price Paid',
                          value: ticket.formattedPrice,
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: 'Purchased',
                          value: _formatDate(ticket.soldAt),
                        ),
                        if (ticket.ownerName != null) ...[
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Holder',
                            value: ticket.ownerName!,
                          ),
                        ],
                        if (ticket.ownerEmail != null) ...[
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Email',
                            value: ticket.ownerEmail!,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Check-in info if used
                  if (ticket.isUsed && ticket.checkedInAt != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Checked In',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                                Text(
                                  _formatDateTime(ticket.checkedInAt!),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDateTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${_formatDate(date)} at $hour:$minute $period';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    Color textColor;
    String label;
    IconData icon;

    switch (ticket.status) {
      case TicketStatus.valid:
        backgroundColor = Colors.green.withValues(alpha: 0.1);
        textColor = Colors.green;
        label = 'Valid';
        icon = Icons.check_circle;
      case TicketStatus.used:
        backgroundColor = Colors.blue.withValues(alpha: 0.1);
        textColor = Colors.blue;
        label = 'Used';
        icon = Icons.verified;
      case TicketStatus.cancelled:
        backgroundColor = Colors.red.withValues(alpha: 0.1);
        textColor = Colors.red;
        label = 'Cancelled';
        icon = Icons.cancel;
      case TicketStatus.refunded:
        backgroundColor = Colors.orange.withValues(alpha: 0.1);
        textColor = Colors.orange;
        label = 'Refunded';
        icon = Icons.undo;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketHeader extends StatelessWidget {
  const _TicketHeader({required this.noiseSeed});

  final int noiseSeed;

  @override
  Widget build(BuildContext context) {
    final config = _getNoiseConfig();

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: config.colors,
            ),
          ),
        ),
        // QR Code placeholder
        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.qr_code_2,
                size: 72,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  NoiseConfig _getNoiseConfig() {
    final presetIndex = noiseSeed % 5;
    return switch (presetIndex) {
      0 => NoisePresets.vibrantEvents(noiseSeed),
      1 => NoisePresets.sunset(noiseSeed),
      2 => NoisePresets.ocean(noiseSeed),
      3 => NoisePresets.subtle(noiseSeed),
      _ => NoisePresets.darkMood(noiseSeed),
    };
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
