import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../notifications/notifications.dart';
import '../../profile/profile.dart';
import '../../tickets/tickets.dart';
import '../../wallet/wallet.dart';
import '../models/event_category.dart';
import '../models/event_model.dart';
import '../widgets/widgets.dart';
import 'event_details_screen.dart';
import 'my_events_screen.dart';

// Local UI state for filters (doesn't need to be global)
final _selectedCategoriesProvider = StateProvider<Set<EventCategory>>((ref) => {});
final _selectedCityProvider = StateProvider<String?>((ref) => null);

/// The main home screen displaying featured events.
///
/// Now uses Riverpod - no more manual listeners or setState for data loading!
class EventsHomeScreen extends ConsumerWidget {
  const EventsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the events state - automatically rebuilds when it changes
    final eventsState = ref.watch(eventsProvider);
    final selectedCategories = ref.watch(_selectedCategoriesProvider);
    final selectedCity = ref.watch(_selectedCityProvider);

    // Compute filtered events
    final filteredEvents = _filterEvents(
      eventsState.events,
      selectedCategories,
      selectedCity,
    );

    // Compute available cities
    final availableCities = eventsState.events
        .map((e) => e.city)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          // Refresh is simple - just call the notifier method
          onRefresh: () => ref.read(eventsProvider.notifier).refresh(),
          child: CustomScrollView(
            slivers: [
              _Header(),
              if (eventsState.isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (eventsState.isUsingPlaceholders)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Showing sample events. Configure Supabase to load real data.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _CarouselSection(events: eventsState.featuredEvents),
                ),
                _SectionHeader(title: 'Upcoming Events'),
                SliverToBoxAdapter(
                  child: EventFilterChips(
                    selectedCategories: selectedCategories,
                    selectedCity: selectedCity,
                    availableCities: availableCities,
                    onCategoriesChanged: (categories) {
                      ref.read(_selectedCategoriesProvider.notifier).state = categories;
                    },
                    onCityChanged: (city) {
                      ref.read(_selectedCityProvider.notifier).state = city;
                    },
                  ),
                ),
                if (filteredEvents.isEmpty)
                  _EmptyFilterState(
                    onClearFilters: () {
                      ref.read(_selectedCategoriesProvider.notifier).state = {};
                      ref.read(_selectedCityProvider.notifier).state = null;
                    },
                  )
                else
                  _EventList(events: filteredEvents),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Filter events by category and city.
  List<EventModel> _filterEvents(
    List<EventModel> events,
    Set<EventCategory> categories,
    String? city,
  ) {
    return events.where((event) {
      // Category filter
      if (categories.isNotEmpty) {
        final eventCategory = event.eventCategory;
        if (eventCategory == null || !categories.contains(eventCategory)) {
          return false;
        }
      }
      // City filter
      if (city != null && event.city != city) {
        return false;
      }
      return true;
    }).toList();
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
            const Spacer(),
            GradientTicketButton(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyTicketsScreen()),
                );
              },
            ),
            const SizedBox(width: 10),
            GradientWalletButton(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WalletScreen()),
                );
              },
            ),
            const SizedBox(width: 10),
            GradientEventsButton(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyEventsScreen()),
                );
              },
            ),
            const SizedBox(width: 10),
            const NotificationBadge(size: 40),
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
        // Featured section
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
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
