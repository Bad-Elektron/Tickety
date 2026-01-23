import 'dart:math';

import 'package:flutter/material.dart';

import '../../tickets/models/ticket_model.dart';
import '../models/event_model.dart';
import '../widgets/scanner_button.dart';
import '../widgets/ticket_info_card.dart';

/// Screen for ushers to scan and validate tickets at an event.
///
/// Features a hold-to-scan button that simulates scanning a ticket
/// and displays the ticket information with validation status.
class UsherEventScreen extends StatefulWidget {
  const UsherEventScreen({
    super.key,
    required this.event,
  });

  final EventModel event;

  @override
  State<UsherEventScreen> createState() => _UsherEventScreenState();
}

class _UsherEventScreenState extends State<UsherEventScreen> {
  TicketModel? _scannedTicket;
  int _scannedCount = 0;
  bool _continuousMode = false;

  void _onScanComplete() {
    // Simulate scanning a random ticket from placeholder data
    final tickets = PlaceholderTickets.forEvent;
    final randomTicket = tickets[Random().nextInt(tickets.length)];

    setState(() {
      _scannedTicket = randomTicket;
    });
  }

  void _onDismiss() {
    setState(() {
      _scannedTicket = null;
    });
  }

  void _onRedeem() {
    setState(() {
      _scannedCount++;
      _scannedTicket = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Ticket redeemed successfully'),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = widget.event.getNoiseConfig();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with gradient
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.event.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 4,
                      color: Colors.black26,
                    ),
                  ],
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: config.colors,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              // Usher badge
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Usher',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Stats bar
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(
                    icon: Icons.qr_code_scanner,
                    value: '$_scannedCount',
                    label: 'Scanned',
                    color: colorScheme.primary,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                  _StatItem(
                    icon: Icons.confirmation_number_outlined,
                    value: '53',
                    label: 'Total Tickets',
                    color: colorScheme.tertiary,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                  _StatItem(
                    icon: Icons.access_time,
                    value: _formatEventTime(widget.event.date),
                    label: 'Event Time',
                    color: colorScheme.secondary,
                  ),
                ],
              ),
            ),
          ),

          // Main content
          SliverFillRemaining(
            hasScrollBody: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.1),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _scannedTicket != null
                  ? _buildTicketResult()
                  : _buildScannerView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    return Center(
      key: const ValueKey('scanner'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          ScannerButton(
            onScanComplete: _onScanComplete,
            holdDuration: const Duration(seconds: 2),
            size: 100,
            continuousMode: _continuousMode,
            onContinuousModeChanged: (value) {
              setState(() => _continuousMode = value);
            },
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _continuousMode
                  ? 'Continuous mode active. Tap the button to scan each ticket.'
                  : 'Position the attendee\'s ticket QR code in front of the device, '
                    'then hold the scan button.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildTicketResult() {
    return SingleChildScrollView(
      key: const ValueKey('result'),
      padding: const EdgeInsets.only(bottom: 32),
      child: TicketInfoCard(
        ticket: _scannedTicket!,
        onDismiss: _onDismiss,
        onRedeem: _onRedeem,
      ),
    );
  }

  String _formatEventTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
