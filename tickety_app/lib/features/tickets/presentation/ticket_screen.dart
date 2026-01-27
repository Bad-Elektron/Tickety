import 'package:flutter/material.dart';

import '../../../core/graphics/graphics.dart';
import '../../staff/models/ticket.dart';

/// Screen displaying details of a single ticket.
///
/// Supports NFC broadcasting for tap-to-check-in on mobile devices.
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.ticket});

  final Ticket ticket;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  bool _nfcAvailable = false;
  bool _nfcBroadcasting = false;

  // Helper getters to extract event data
  String get _eventTitle =>
      widget.ticket.eventData?['title'] as String? ?? 'Unknown Event';

  String? get _eventSubtitle =>
      widget.ticket.eventData?['subtitle'] as String?;

  String? get _venue => widget.ticket.eventData?['venue'] as String?;

  String? get _city => widget.ticket.eventData?['city'] as String?;

  String? get _country => widget.ticket.eventData?['country'] as String?;

  DateTime? get _eventDate {
    final dateStr = widget.ticket.eventData?['date'] as String?;
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  int get _noiseSeed =>
      widget.ticket.eventData?['noise_seed'] as int? ??
      widget.ticket.ticketNumber.hashCode;

  String? get _fullAddress {
    final parts = <String>[];
    if (_venue != null) parts.add(_venue!);
    if (_city != null) parts.add(_city!);
    if (_country != null) parts.add(_country!);
    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  @override
  void initState() {
    super.initState();
    // NFC temporarily disabled
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _toggleNfcBroadcast() {
    // NFC temporarily disabled
    _showMessage('NFC is temporarily unavailable. Please use QR code.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
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
              background: _TicketHeader(
                noiseSeed: _noiseSeed,
                ticketNumber: widget.ticket.ticketNumber,
                nfcAvailable: _nfcAvailable,
                nfcBroadcasting: _nfcBroadcasting,
                onNfcToggle: _toggleNfcBroadcast,
              ),
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

                  // NFC Check-in card (if available and ticket is valid)
                  if (_nfcAvailable && widget.ticket.isValid) ...[
                    _NfcCheckInCard(
                      isActive: _nfcBroadcasting,
                      onToggle: _toggleNfcBroadcast,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Ticket number
                  _InfoCard(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Ticket Number',
                    value: widget.ticket.ticketNumber,
                    trailing: _StatusBadge(ticket: widget.ticket),
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
                          value: widget.ticket.formattedPrice,
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: 'Purchased',
                          value: _formatDate(widget.ticket.soldAt),
                        ),
                        if (widget.ticket.ownerName != null) ...[
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Holder',
                            value: widget.ticket.ownerName!,
                          ),
                        ],
                        if (widget.ticket.ownerEmail != null) ...[
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Email',
                            value: widget.ticket.ownerEmail!,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Check-in info if used
                  if (widget.ticket.isUsed && widget.ticket.checkedInAt != null) ...[
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
                                  _formatDateTime(widget.ticket.checkedInAt!),
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

                  // Discover more events button
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        // Pop back to home screen
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      icon: const Icon(Icons.explore_outlined),
                      label: const Text('Discover More Events'),
                    ),
                  ),
                  const SizedBox(height: 16),
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

/// NFC tap-to-check-in card.
class _NfcCheckInCard extends StatelessWidget {
  const _NfcCheckInCard({
    required this.isActive,
    required this.onToggle,
  });

  final bool isActive;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isActive
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  colorScheme.primary.withValues(alpha: 0.8),
                ],
              )
            : null,
        color: isActive ? null : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: isActive
            ? null
            : Border.all(
                color: colorScheme.outline.withValues(alpha: 0.3),
              ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // NFC icon with animation
          _AnimatedNfcIcon(isActive: isActive),
          const SizedBox(width: 16),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Ready to Tap' : 'Tap to Check In',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive
                      ? 'Hold phone near usher device'
                      : 'Enable NFC for instant check-in',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.9)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Toggle button
          Switch(
            value: isActive,
            onChanged: (_) => onToggle(),
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return null;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white.withValues(alpha: 0.3);
              }
              return null;
            }),
          ),
        ],
      ),
    );
  }
}

/// Animated NFC icon with pulse effect when active.
class _AnimatedNfcIcon extends StatefulWidget {
  const _AnimatedNfcIcon({required this.isActive});

  final bool isActive;

  @override
  State<_AnimatedNfcIcon> createState() => _AnimatedNfcIconState();
}

class _AnimatedNfcIconState extends State<_AnimatedNfcIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_AnimatedNfcIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.repeat();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulse rings when active
          if (widget.isActive)
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Container(
                  width: 48 + (16 * _animation.value),
                  height: 48 + (16 * _animation.value),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 1.0 - _animation.value),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
          // Icon background
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? Colors.white.withValues(alpha: 0.2)
                  : colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.nfc_rounded,
              size: 24,
              color: widget.isActive ? Colors.white : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
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
  const _TicketHeader({
    required this.noiseSeed,
    required this.ticketNumber,
    required this.nfcAvailable,
    required this.nfcBroadcasting,
    required this.onNfcToggle,
  });

  final int noiseSeed;
  final String ticketNumber;
  final bool nfcAvailable;
  final bool nfcBroadcasting;
  final VoidCallback onNfcToggle;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
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
              // NFC indicator when broadcasting
              if (nfcBroadcasting) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'NFC Ready',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
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
