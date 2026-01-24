import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../../core/services/services.dart';
import '../../staff/data/staff_repository.dart';
import '../../staff/models/staff_role.dart';
import '../data/data.dart';
import '../models/event_model.dart';
import 'admin_event_screen.dart';
import 'create_event_screen.dart';
import 'usher_event_screen.dart';
import 'vendor_event_screen.dart';

/// Screen displaying events the user is involved with (created or ushering).
///
/// Uses Riverpod for created events - cleaner state management!
class MyEventsScreen extends ConsumerStatefulWidget {
  const MyEventsScreen({super.key});

  @override
  ConsumerState<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends ConsumerState<MyEventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _staffRepository = StaffRepository();

  List<_StaffEventData> _usheringEvents = [];
  List<_StaffEventData> _sellingEvents = [];

  bool _isLoadingStaff = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadStaffEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStaffEvents() async {
    if (!SupabaseService.instance.isAuthenticated) {
      setState(() {
        _usheringEvents = [];
        _sellingEvents = [];
        _isLoadingStaff = false;
      });
      return;
    }

    try {
      final staffAssignments = await _staffRepository.getMyStaffEvents();
      final ushering = <_StaffEventData>[];
      final selling = <_StaffEventData>[];

      for (final assignment in staffAssignments) {
        final eventData = assignment['events'] as Map<String, dynamic>?;
        if (eventData != null) {
          final event = EventMapper.fromJson(eventData);
          final staff = EventStaff.fromJson(assignment);

          // Check what roles this user has for this event
          final canUsher = staff.role == StaffRole.usher || staff.role == StaffRole.manager;
          final canSell = staff.role == StaffRole.seller || staff.role == StaffRole.manager;

          final data = _StaffEventData(
            event: event,
            canUsher: canUsher,
            canSell: canSell,
          );

          if (canUsher) ushering.add(data);
          if (canSell) selling.add(data);
        }
      }

      if (mounted) {
        setState(() {
          _usheringEvents = ushering;
          _sellingEvents = selling;
          _isLoadingStaff = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStaff = false);
        // Staff events failing silently is OK - user might not have any
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Watch my events state from Riverpod - auto rebuilds!
    final myEventsState = ref.watch(myEventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Events'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.admin_panel_settings_outlined),
              text: 'Created',
            ),
            Tab(
              icon: Icon(Icons.badge_outlined),
              text: 'Ushering',
            ),
            Tab(
              icon: Icon(Icons.point_of_sale_outlined),
              text: 'Selling',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Created events tab - using Riverpod
          myEventsState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : myEventsState.events.isEmpty
                  ? _buildEmptyCreatedState(theme, colorScheme)
                  : _buildCreatedEventsList(myEventsState.events),
          // Ushering events tab
          _isLoadingStaff
              ? const Center(child: CircularProgressIndicator())
              : _usheringEvents.isEmpty
                  ? _buildEmptyUsheringState(theme, colorScheme)
                  : _buildUsheringEventsList(),
          // Selling events tab
          _isLoadingStaff
              ? const Center(child: CircularProgressIndicator())
              : _sellingEvents.isEmpty
                  ? _buildEmptySellingState(theme, colorScheme)
                  : _buildSellingEventsList(),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          // Only show FAB on "Created" tab
          final showFab = _tabController.index == 0;
          return AnimatedScale(
            scale: showFab ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedOpacity(
              opacity: showFab ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: FloatingActionButton.extended(
                onPressed: showFab
                    ? () async {
                        final result = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => const CreateEventScreen(),
                          ),
                        );
                        // Refresh if event was created
                        if (result == true) {
                          ref.read(myEventsProvider.notifier).refresh();
                        }
                      }
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Create Event'),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyCreatedState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_outlined,
                size: 56,
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'No events yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create your first event and\nstart selling tickets.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyUsheringState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.badge_outlined,
                size: 56,
                color: colorScheme.tertiary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'No usher assignments',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'When event organizers add you as an\nusher, those events will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreatedEventsList(List<EventModel> events) {
    return RefreshIndicator(
      onRefresh: () => ref.read(myEventsProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final event = events[index];
          return _MyEventCard(
            event: event,
            badgeLabel: 'Admin',
            badgeIcon: Icons.admin_panel_settings,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminEventScreen(event: event),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildUsheringEventsList() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: _usheringEvents.length,
      itemBuilder: (context, index) {
        final data = _usheringEvents[index];
        return _MyEventCard(
          event: data.event,
          badgeLabel: 'Usher',
          badgeIcon: Icons.badge_outlined,
          badgeColor: Theme.of(context).colorScheme.tertiary,
          showRoleSwitch: data.canSell,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UsherEventScreen(
                  event: data.event,
                  canSwitchToSelling: data.canSell,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptySellingState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.point_of_sale_outlined,
                size: 56,
                color: Colors.green.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'No vendor assignments',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'When event organizers add you as a\nvendor, those events will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellingEventsList() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: _sellingEvents.length,
      itemBuilder: (context, index) {
        final data = _sellingEvents[index];
        return _MyEventCard(
          event: data.event,
          badgeLabel: 'Vendor',
          badgeIcon: Icons.point_of_sale,
          badgeColor: Colors.green,
          showRoleSwitch: data.canUsher,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VendorEventScreen(
                  event: data.event,
                  canSwitchToUsher: data.canUsher,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Data class to track staff roles for an event.
class _StaffEventData {
  final EventModel event;
  final bool canUsher;
  final bool canSell;

  const _StaffEventData({
    required this.event,
    this.canUsher = false,
    this.canSell = false,
  });
}

class _MyEventCard extends StatelessWidget {
  final EventModel event;
  final String badgeLabel;
  final IconData badgeIcon;
  final Color? badgeColor;
  final VoidCallback onTap;
  final bool showRoleSwitch;

  const _MyEventCard({
    required this.event,
    required this.badgeLabel,
    required this.badgeIcon,
    required this.onTap,
    this.badgeColor,
    this.showRoleSwitch = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = event.getNoiseConfig();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gradient header
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
                    // Role badge
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showRoleSwitch)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.swap_horiz,
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '2 roles',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  badgeIcon,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  badgeLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    // Stats row
                    Row(
                      children: [
                        _StatChip(
                          icon: Icons.confirmation_number_outlined,
                          label: '53 sold',
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        _StatChip(
                          icon: Icons.calendar_today_outlined,
                          label: _formatDate(event.date),
                          color: badgeColor ?? colorScheme.tertiary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff < 7) return 'In $diff days';

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
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
