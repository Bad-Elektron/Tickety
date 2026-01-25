import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/providers/providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../../staff/models/ticket.dart';
import 'ticket_screen.dart';

/// Screen displaying the user's purchased tickets.
class MyTicketsScreen extends ConsumerStatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  ConsumerState<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends ConsumerState<MyTicketsScreen> {
  @override
  void initState() {
    super.initState();
    // Load tickets when screen opens
    Future.microtask(() {
      ref.read(myTicketsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ticketsState = ref.watch(myTicketsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tickets'),
        centerTitle: true,
      ),
      body: ticketsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ticketsState.error != null
              ? _buildErrorState(context, ticketsState.error!, theme, colorScheme)
              : ticketsState.tickets.isEmpty
                  ? _buildEmptyState(context, theme, colorScheme)
                  : RefreshIndicator(
                      onRefresh: () => ref.read(myTicketsProvider.notifier).refresh(),
                      child: _buildTicketList(context, ticketsState.tickets),
                    ),
    );
  }

  Widget _buildTicketList(BuildContext context, List<Ticket> tickets) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tickets.length,
      itemBuilder: (context, index) {
        final ticket = tickets[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TicketCard(ticket: ticket),
        );
      },
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    String error,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return ErrorDisplay.generic(
      message: error,
      onRetry: () => ref.read(myTicketsProvider.notifier).refresh(),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Large ticket icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: CustomPaint(
                  size: const Size(60, 42),
                  painter: _TicketIconPainter(
                    color: colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'No tickets yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'When you purchase tickets to events,\nthey\'ll appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.explore_outlined),
              label: const Text('Discover Events'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});

  final Ticket ticket;

  String get _eventTitle =>
      ticket.eventData?['title'] as String? ?? 'Unknown Event';

  String? get _venue => ticket.eventData?['venue'] as String?;

  DateTime? get _eventDate {
    final dateStr = ticket.eventData?['date'] as String?;
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  int get _noiseSeed =>
      ticket.eventData?['noise_seed'] as int? ?? ticket.ticketNumber.hashCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = _getNoiseConfig();

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TicketScreen(ticket: ticket),
            ),
          );
        },
        child: Column(
          children: [
            // Gradient header with event info
            Container(
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: config.colors,
                ),
              ),
              child: Stack(
                children: [
                  // Event title
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _eventTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ticket.ticketNumber,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  if (ticket.isUsed)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Used',
                              style: theme.textTheme.labelSmall?.copyWith(
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
            // Ticket details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Date
                  Expanded(
                    child: _TicketDetail(
                      icon: Icons.calendar_today_outlined,
                      label: 'Date',
                      value: _eventDate != null
                          ? _formatDate(_eventDate!)
                          : 'TBA',
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: colorScheme.outlineVariant,
                  ),
                  // Price
                  Expanded(
                    child: _TicketDetail(
                      icon: Icons.confirmation_number_outlined,
                      label: 'Price',
                      value: ticket.formattedPrice,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: colorScheme.outlineVariant,
                  ),
                  // Location
                  Expanded(
                    child: _TicketDetail(
                      icon: Icons.location_on_outlined,
                      label: 'Venue',
                      value: _venue ?? 'TBA',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  NoiseConfig _getNoiseConfig() {
    final presetIndex = _noiseSeed % 5;
    return switch (presetIndex) {
      0 => NoisePresets.vibrantEvents(_noiseSeed),
      1 => NoisePresets.sunset(_noiseSeed),
      2 => NoisePresets.ocean(_noiseSeed),
      3 => NoisePresets.subtle(_noiseSeed),
      _ => NoisePresets.darkMood(_noiseSeed),
    };
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _TicketDetail extends StatelessWidget {
  const _TicketDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Icon(
          icon,
          size: 18,
          color: colorScheme.primary,
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Custom ticket icon painter.
class _TicketIconPainter extends CustomPainter {
  final Color color;

  _TicketIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final notchRadius = h * 0.15;
    final cornerRadius = h * 0.15;

    final path = Path();

    path.moveTo(cornerRadius, 0);
    path.lineTo(w - cornerRadius, 0);
    path.quadraticBezierTo(w, 0, w, cornerRadius);

    path.lineTo(w, h * 0.35);
    path.arcToPoint(
      Offset(w, h * 0.65),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.lineTo(w, h - cornerRadius);
    path.quadraticBezierTo(w, h, w - cornerRadius, h);

    path.lineTo(cornerRadius, h);
    path.quadraticBezierTo(0, h, 0, h - cornerRadius);

    path.lineTo(0, h * 0.65);
    path.arcToPoint(
      Offset(0, h * 0.35),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.lineTo(0, cornerRadius);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);

    canvas.drawPath(path, paint);

    final dashPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03;

    final dashX = w * 0.35;
    const dashCount = 4;
    final dashHeight = h * 0.12;
    final dashGap = (h - dashHeight * dashCount) / (dashCount + 1);

    for (var i = 0; i < dashCount; i++) {
      final y = dashGap * (i + 1) + dashHeight * i;
      canvas.drawLine(
        Offset(dashX, y),
        Offset(dashX, y + dashHeight),
        dashPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TicketIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
