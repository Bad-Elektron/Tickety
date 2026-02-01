import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../events/data/data.dart';
import '../../events/models/event_model.dart';
import '../data/ticket_repository.dart';
import '../models/staff_role.dart';
import 'vendor_pos_screen.dart';

/// Dashboard for staff members to access their assigned events.
class StaffDashboardScreen extends ConsumerStatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  ConsumerState<StaffDashboardScreen> createState() =>
      _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends ConsumerState<StaffDashboardScreen> {
  List<_StaffEventData> _staffEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStaffEvents();
  }

  Future<void> _loadStaffEvents() async {
    setState(() => _isLoading = true);

    try {
      final staffRepository = ref.read(staffRepositoryProvider);
      final ticketRepository = ref.read(ticketRepositoryProvider);

      final staffResult = await staffRepository.getMyStaffEvents();
      final events = <_StaffEventData>[];

      for (final assignment in staffResult.items) {
        final eventData = assignment['events'] as Map<String, dynamic>?;
        if (eventData != null) {
          final event = EventMapper.fromJson(eventData);
          final staff = EventStaff.fromJson(assignment);
          final stats = await ticketRepository.getTicketStats(event.id);
          events.add(_StaffEventData(event: event, staff: staff, stats: stats));
        }
      }

      setState(() => _staffEvents = events);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load events: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Dashboard'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _staffEvents.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  onRefresh: _loadStaffEvents,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _staffEvents.length,
                    itemBuilder: (context, index) {
                      final data = _staffEvents[index];
                      return _EventCard(
                        data: data,
                        onSellTickets: () => _navigateToSellTickets(data.event),
                        onCheckTickets: () => _navigateToCheckTickets(data.event),
                      );
                    },
                  ),
                ),
    );
  }

  void _navigateToSellTickets(EventModel event) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VendorPOSScreen(event: event),
      ),
    );
  }

  void _navigateToCheckTickets(EventModel event) {
    // TODO: Navigate to ticket check screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ticket scanning coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.badge_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No staff assignments',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You are not assigned as staff to any events yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final _StaffEventData data;
  final VoidCallback onSellTickets;
  final VoidCallback onCheckTickets;

  const _EventCard({
    required this.data,
    required this.onSellTickets,
    required this.onCheckTickets,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.event.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data.event.displayLocation ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getRoleColor(data.staff.role).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getRoleIcon(data.staff.role),
                        size: 16,
                        color: _getRoleColor(data.staff.role),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        data.staff.role.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _getRoleColor(data.staff.role),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats row
            Row(
              children: [
                _StatChip(
                  icon: Icons.confirmation_number,
                  label: '${data.stats.totalSold} sold',
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                _StatChip(
                  icon: Icons.login,
                  label: '${data.stats.checkedIn} checked in',
                  color: Colors.green,
                ),
                const SizedBox(width: 12),
                _StatChip(
                  icon: Icons.attach_money,
                  label: data.stats.formattedRevenue,
                  color: Colors.amber.shade700,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                if (data.staff.canSellTickets)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onSellTickets,
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Sell Tickets'),
                    ),
                  ),
                if (data.staff.canSellTickets) const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCheckTickets,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Check Tickets'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(StaffRole role) {
    return switch (role) {
      StaffRole.usher => Colors.blue,
      StaffRole.seller => Colors.green,
      StaffRole.manager => Colors.purple,
    };
  }

  IconData _getRoleIcon(StaffRole role) {
    return switch (role) {
      StaffRole.usher => Icons.qr_code_scanner,
      StaffRole.seller => Icons.point_of_sale,
      StaffRole.manager => Icons.admin_panel_settings,
    };
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffEventData {
  final EventModel event;
  final EventStaff staff;
  final TicketStats stats;

  _StaffEventData({
    required this.event,
    required this.staff,
    required this.stats,
  });
}
