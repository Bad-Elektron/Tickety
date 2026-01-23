import 'package:flutter/material.dart';

import '../../profile/profile.dart';
import '../../search/search.dart';
import '../../tickets/tickets.dart';
import '../../wallet/wallet.dart';
import '../models/event_category.dart';
import '../models/event_model.dart';
import '../widgets/widgets.dart';
import 'event_details_screen.dart';
import 'my_events_screen.dart';

/// The main home screen displaying featured events.
class EventsHomeScreen extends StatefulWidget {
  const EventsHomeScreen({super.key});

  @override
  State<EventsHomeScreen> createState() => _EventsHomeScreenState();
}

class _EventsHomeScreenState extends State<EventsHomeScreen> {
  final List<EventModel> _allEvents = PlaceholderEvents.upcoming;
  Set<EventCategory> _selectedCategories = {};
  String? _selectedCity;

  /// Cached list of unique cities from all events.
  late final List<String> _availableCities = _allEvents
      .map((e) => e.city)
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();

  /// Events filtered by selected categories and city.
  List<EventModel> get _filteredEvents {
    return _allEvents.where((event) {
      // Category filter
      if (_selectedCategories.isNotEmpty) {
        final eventCategory = event.eventCategory;
        if (eventCategory == null || !_selectedCategories.contains(eventCategory)) {
          return false;
        }
      }

      // City filter
      if (_selectedCity != null && event.city != _selectedCity) {
        return false;
      }

      return true;
    }).toList();
  }

  void _onCategoriesChanged(Set<EventCategory> categories) {
    setState(() => _selectedCategories = categories);
  }

  void _onCityChanged(String? city) {
    setState(() => _selectedCity = city);
  }

  @override
  Widget build(BuildContext context) {
    final filteredEvents = _filteredEvents;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _Header(),
            SliverToBoxAdapter(
              child: _CarouselSection(events: _allEvents),
            ),
            _SectionHeader(title: 'Upcoming Events'),
            SliverToBoxAdapter(
              child: EventFilterChips(
                selectedCategories: _selectedCategories,
                selectedCity: _selectedCity,
                availableCities: _availableCities,
                onCategoriesChanged: _onCategoriesChanged,
                onCityChanged: _onCityChanged,
              ),
            ),
            if (filteredEvents.isEmpty)
              _EmptyFilterState(
                onClearFilters: () {
                  setState(() {
                    _selectedCategories = {};
                    _selectedCity = null;
                  });
                },
              )
            else
              _EventList(events: filteredEvents),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            ProfileAvatar(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discover',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Find your next experience',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            GradientSearchButton(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
            ),
            const SizedBox(width: 12),
            GradientTicketButton(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyTicketsScreen()),
                );
              },
            ),
            const SizedBox(width: 12),
            GradientWalletButton(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WalletScreen()),
                );
              },
            ),
            const SizedBox(width: 12),
            GradientEventsButton(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyEventsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CarouselSection extends StatelessWidget {
  final List<EventModel> events;

  const _CarouselSection({required this.events});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Text(
            'Featured',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        EventBannerCarousel(
          events: events,
          config: const EventCarouselConfig(
            height: 280,
            viewportFraction: 0.88,
          ),
          onEventTapped: (event) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EventDetailsScreen(event: event),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('See all'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  final List<EventModel> events;

  const _EventList({required this.events});

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _EventListTile(event: events[index]),
        childCount: events.length,
      ),
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  final VoidCallback onClearFilters;

  const _EmptyFilterState({required this.onClearFilters});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No events found',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your filters to find more events',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: const Text('Clear Filters'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventListTile extends StatelessWidget {
  final EventModel event;

  const _EventListTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: _Thumbnail(event: event),
      title: Text(
        event.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            _formatDate(event.date),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          if (event.displayLocation != null)
            Text(
              event.displayLocation!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: Text(
        event.formattedPrice,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: event.isFree
              ? Colors.green
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailsScreen(event: event),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    final difference = date.difference(now).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _Thumbnail extends StatelessWidget {
  final EventModel event;

  const _Thumbnail({required this.event});

  @override
  Widget build(BuildContext context) {
    final config = event.getNoiseConfig();

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: config.colors,
          ),
        ),
        child: const SizedBox(width: 56, height: 56),
      ),
    );
  }
}
