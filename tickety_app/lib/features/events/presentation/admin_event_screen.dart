import 'package:flutter/material.dart';

import '../../../shared/widgets/widgets.dart';
import '../models/event_model.dart';
import 'event_data_screen.dart';

/// Admin screen for managing an event created by the user.
class AdminEventScreen extends StatelessWidget {
  final EventModel event;

  const AdminEventScreen({
    super.key,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = event.getNoiseConfig();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero header
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  GradientBackground(colors: config.colors),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x80000000),
                        ],
                      ),
                    ),
                  ),
                  // Admin badge
                  Positioned(
                    top: 100,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.admin_panel_settings,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Event Admin',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
                  // Title
                  Text(
                    event.title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event.subtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Stats cards
                  _StatsSection(),
                  const SizedBox(height: 24),
                  // Admin actions
                  Text(
                    'Admin Actions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _AdminActionCard(
                    icon: Icons.pie_chart,
                    title: 'Data',
                    subtitle: 'View event analytics and statistics',
                    color: Colors.deepPurple,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EventDataScreen(event: event),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.confirmation_number,
                    title: 'Mint Tickets',
                    subtitle: 'Create more tickets for this event',
                    color: colorScheme.primary,
                    onTap: () => _showMintTicketsSheet(context),
                  ),
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.content_cut,
                    customIcon: const _TicketTearIcon(size: 28),
                    title: 'Manage Ushers',
                    subtitle: 'Add credential checkers for entry',
                    color: colorScheme.tertiary,
                    onTap: () => _showManageUshersSheet(context),
                  ),
                  const SizedBox(height: 12),
                  _AdminActionCard(
                    icon: Icons.edit_outlined,
                    title: 'Edit Event',
                    subtitle: 'Update event details',
                    color: colorScheme.secondary,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Coming soon'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  // Event info
                  Text(
                    'Event Details',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.calendar_today_rounded,
                    title: 'Date & Time',
                    value: _formatDateTime(event.date),
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  if (event.location != null)
                    _InfoCard(
                      icon: Icons.location_on_outlined,
                      title: 'Location',
                      value: event.location!,
                      color: colorScheme.tertiary,
                    ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    icon: Icons.attach_money,
                    title: 'Ticket Price',
                    value: event.formattedPrice,
                    color: colorScheme.secondary,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];

    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    final day = date.day;
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$weekday, $month $day at $hour:$minute $period';
  }

  void _showMintTicketsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _MintTicketsSheet(),
    );
  }

  void _showManageUshersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ManageUshersSheet(),
    );
  }
}

class _StatsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Tickets Sold',
            value: '53',
            total: '100',
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Revenue',
            value: '\$530',
            color: colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Ushers',
            value: '2',
            color: colorScheme.tertiary,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? total;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (total != null) ...[
                Text(
                  '/$total',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminActionCard extends StatelessWidget {
  final IconData icon;
  final Widget? customIcon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminActionCard({
    required this.icon,
    this.customIcon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: customIcon ?? Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom icon showing a ticket being torn/cut.
class _TicketTearIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const _TicketTearIcon({
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.tertiary;

    return CustomPaint(
      size: Size(size, size * 0.7),
      painter: _TicketTearPainter(color: iconColor),
    );
  }
}

class _TicketTearPainter extends CustomPainter {
  final Color color;

  _TicketTearPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final gap = w * 0.08;
    final leftW = w * 0.45 - gap / 2;
    final rightX = w * 0.55 + gap / 2;
    final rightW = w - rightX;

    // Left ticket half
    _drawTicketHalf(canvas, paint, 0, 0, leftW, h, true);

    // Right ticket half (slightly rotated/offset to show tear)
    canvas.save();
    canvas.translate(rightX, h * 0.05);
    canvas.rotate(0.05);
    _drawTicketHalf(canvas, paint, 0, 0, rightW, h * 0.95, false);
    canvas.restore();

    // Tear marks (zigzag line)
    final tearPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03;

    final tearPath = Path();
    final tearX = w * 0.48;
    tearPath.moveTo(tearX, 0);
    for (var i = 0; i < 5; i++) {
      final y1 = h * (i * 2 + 1) / 10;
      final y2 = h * (i * 2 + 2) / 10;
      tearPath.lineTo(tearX + (i.isEven ? w * 0.03 : -w * 0.03), y1);
      tearPath.lineTo(tearX, y2);
    }
    canvas.drawPath(tearPath, tearPaint);
  }

  void _drawTicketHalf(
    Canvas canvas,
    Paint paint,
    double x,
    double y,
    double w,
    double h,
    bool isLeft,
  ) {
    final notchRadius = h * 0.12;
    final cornerRadius = h * 0.12;

    final path = Path();

    if (isLeft) {
      path.moveTo(x + cornerRadius, y);
      path.lineTo(x + w, y);
      path.lineTo(x + w, y + h * 0.35);
      path.arcToPoint(
        Offset(x + w, y + h * 0.65),
        radius: Radius.circular(notchRadius),
        clockwise: false,
      );
      path.lineTo(x + w, y + h);
      path.lineTo(x + cornerRadius, y + h);
      path.quadraticBezierTo(x, y + h, x, y + h - cornerRadius);
      path.lineTo(x, y + cornerRadius);
      path.quadraticBezierTo(x, y, x + cornerRadius, y);
    } else {
      path.moveTo(x, y);
      path.lineTo(x + w - cornerRadius, y);
      path.quadraticBezierTo(x + w, y, x + w, y + cornerRadius);
      path.lineTo(x + w, y + h - cornerRadius);
      path.quadraticBezierTo(x + w, y + h, x + w - cornerRadius, y + h);
      path.lineTo(x, y + h);
      path.lineTo(x, y + h * 0.65);
      path.arcToPoint(
        Offset(x, y + h * 0.35),
        radius: Radius.circular(notchRadius),
        clockwise: false,
      );
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TicketTearPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Bottom sheet for minting more tickets.
class _MintTicketsSheet extends StatefulWidget {
  const _MintTicketsSheet();

  @override
  State<_MintTicketsSheet> createState() => _MintTicketsSheetState();
}

class _MintTicketsSheetState extends State<_MintTicketsSheet> {
  int _quantity = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Icon(
            Icons.confirmation_number,
            size: 48,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Mint More Tickets',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Current supply: 100 tickets',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MintButton(
                icon: Icons.remove,
                onTap: _quantity > 1 ? () => setState(() => _quantity -= 10) : null,
              ),
              const SizedBox(width: 24),
              Text(
                '$_quantity',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 24),
              _MintButton(
                icon: Icons.add,
                onTap: _quantity < 100 ? () => setState(() => _quantity += 10) : null,
              ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Minted $_quantity new tickets'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Mint Tickets',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MintButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _MintButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onTap != null;

    return Material(
      color: isEnabled ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(
            icon,
            color: isEnabled ? colorScheme.onPrimaryContainer : colorScheme.onSurface.withValues(alpha: 0.3),
            size: 28,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for managing ushers.
class _ManageUshersSheet extends StatelessWidget {
  const _ManageUshersSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final ushers = [
      {'name': 'Alex Johnson', 'email': 'alex@email.com'},
      {'name': 'Sam Wilson', 'email': 'sam@email.com'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _TicketTearIcon(size: 32, color: colorScheme.tertiary),
              const SizedBox(width: 12),
              Text(
                'Manage Ushers',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ushers can scan tickets and admit guests',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          // Current ushers
          ...ushers.map((usher) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.tertiaryContainer,
                    child: Text(
                      usher['name']![0],
                      style: TextStyle(color: colorScheme.onTertiaryContainer),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          usher['name']!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          usher['email']!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.remove_circle_outline, color: colorScheme.error),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          )),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Coming soon'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Add Usher'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
