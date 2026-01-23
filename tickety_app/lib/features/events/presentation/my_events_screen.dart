import 'package:flutter/material.dart';

import '../models/event_model.dart';
import 'admin_event_screen.dart';
import 'create_event_screen.dart';
import 'usher_event_screen.dart';

/// Screen displaying events the user is involved with (created or ushering).
class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({super.key});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Placeholder events created by user
  final List<EventModel> _createdEvents = [
    EventModel(
      id: 'my_evt_001',
      title: 'Birthday Bash 2025',
      subtitle: 'Celebrating another year around the sun',
      description: 'Join us for an unforgettable birthday celebration with '
          'music, food, and great company. Dress code: Party casual.',
      date: DateTime.now().add(const Duration(days: 21)),
      venue: 'Rooftop Lounge',
      city: 'Downtown',
      category: 'Party',
      priceInCents: 1000,
      noiseSeed: 333,
    ),
  ];

  // Placeholder events the user is ushering for
  final List<EventModel> _usheringEvents = [
    EventModel(
      id: 'usher_evt_001',
      title: 'Summer Music Festival',
      subtitle: 'Three days of incredible live performances',
      description: 'Join us for the biggest music festival of the summer.',
      date: DateTime.now().add(const Duration(days: 2)),
      venue: 'Central Park',
      city: 'New York',
      category: 'Music',
      priceInCents: 7500,
      noiseSeed: 42,
    ),
    EventModel(
      id: 'usher_evt_002',
      title: 'Tech Conference 2025',
      subtitle: 'The future of technology is here',
      description: 'Learn about the latest innovations in AI and more.',
      date: DateTime.now().add(const Duration(days: 7)),
      venue: 'Convention Center',
      city: 'San Francisco',
      category: 'Technology',
      priceInCents: 29900,
      noiseSeed: 108,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Created events tab
          _createdEvents.isEmpty
              ? _buildEmptyCreatedState(theme, colorScheme)
              : _buildCreatedEventsList(),
          // Ushering events tab
          _usheringEvents.isEmpty
              ? _buildEmptyUsheringState(theme, colorScheme)
              : _buildUsheringEventsList(),
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
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CreateEventScreen(),
                          ),
                        );
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

  Widget _buildCreatedEventsList() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: _createdEvents.length,
      itemBuilder: (context, index) {
        final event = _createdEvents[index];
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
    );
  }

  Widget _buildUsheringEventsList() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: _usheringEvents.length,
      itemBuilder: (context, index) {
        final event = _usheringEvents[index];
        return _MyEventCard(
          event: event,
          badgeLabel: 'Usher',
          badgeIcon: Icons.badge_outlined,
          badgeColor: Theme.of(context).colorScheme.tertiary,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UsherEventScreen(event: event),
              ),
            );
          },
        );
      },
    );
  }
}

class _MyEventCard extends StatelessWidget {
  final EventModel event;
  final String badgeLabel;
  final IconData badgeIcon;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _MyEventCard({
    required this.event,
    required this.badgeLabel,
    required this.badgeIcon,
    required this.onTap,
    this.badgeColor,
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
                      child: Container(
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
