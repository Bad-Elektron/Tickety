import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/providers.dart';
import '../../external_events/external_events.dart';
import '../../notifications/notifications.dart';
import '../../profile/profile.dart';
import '../../tickets/tickets.dart';
import '../../subscriptions/models/tier_limits.dart';
import '../../venues/presentation/venues_screen.dart';
import '../../wallet/wallet.dart';
import '../data/supabase_event_repository.dart';
import '../models/event_category.dart';
import '../models/event_model.dart';
import '../widgets/widgets.dart';
import 'event_details_screen.dart';
import 'my_events_screen.dart';

// Local UI state for filters (doesn't need to be global)
final _selectedCategoriesProvider = StateProvider<Set<EventCategory>>((ref) => {});
final _selectedCityProvider = StateProvider<String?>((ref) => null);
final _selectedTagsProvider = StateProvider<Set<String>>((ref) => {});

/// The main home screen displaying featured events.
///
/// Now uses Riverpod - no more manual listeners or setState for data loading!
class EventsHomeScreen extends ConsumerStatefulWidget {
  const EventsHomeScreen({super.key});

  @override
  ConsumerState<EventsHomeScreen> createState() => _EventsHomeScreenState();
}

class _EventsHomeScreenState extends ConsumerState<EventsHomeScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  bool _isSearching = false;
  String _searchQuery = '';
  EventModel? _inviteCodeResult;
  List<EventModel> _serverSearchResults = [];
  bool _isServerSearching = false;
  final _eventRepo = SupabaseEventRepository();

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final trimmed = value.trim();
      setState(() {
        _searchQuery = trimmed.toLowerCase();
      });
      // Check for invite code pattern (8 alphanumeric chars)
      final upper = trimmed.toUpperCase();
      if (RegExp(r'^[A-Z0-9]{8}$').hasMatch(upper)) {
        _eventRepo.getEventByInviteCode(upper).then((event) {
          if (mounted) setState(() => _inviteCodeResult = event);
        });
      } else {
        if (_inviteCodeResult != null) {
          setState(() => _inviteCodeResult = null);
        }
      }
      // Server-side search for events not in the feed
      if (trimmed.length >= 2) {
        setState(() => _isServerSearching = true);
        _eventRepo.searchEvents(trimmed).then((results) {
          if (mounted) {
            setState(() {
              _serverSearchResults = results;
              _isServerSearching = false;
            });
          }
        }).catchError((_) {
          if (mounted) setState(() => _isServerSearching = false);
        });
      } else {
        setState(() => _serverSearchResults = []);
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      if (_isSearching) {
        _searchController.clear();
        _searchFocusNode.unfocus();
        _searchQuery = '';
        _inviteCodeResult = null;
        _serverSearchResults = [];
      }
      _isSearching = !_isSearching;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch discovery feed (scored) + external events
    final discoveryState = ref.watch(discoveryFeedProvider);
    final eventsState = ref.watch(eventsProvider);
    final externalState = ref.watch(externalEventsProvider);
    final selectedCategories = ref.watch(_selectedCategoriesProvider);
    final selectedCity = ref.watch(_selectedCityProvider);
    final selectedTags = ref.watch(_selectedTagsProvider);

    // Build mixed feed: scored native events + external events
    // Native events come from discovery feed (already scored/ranked)
    final nativeItems = discoveryState.events.map(NativeEventFeedItem.new).toList();
    final externalItems = externalState.events.map(ExternalEventFeedItem.new).toList();
    // Keep native items in score order (don't re-sort by date)
    final allItems = [...nativeItems, ...externalItems];

    // When searching, merge server search results (deduped) into feed items
    if (_searchQuery.isNotEmpty && _serverSearchResults.isNotEmpty) {
      final existingIds = allItems
          .whereType<NativeEventFeedItem>()
          .map((i) => i.event.id)
          .toSet();
      for (final event in _serverSearchResults) {
        if (!existingIds.contains(event.id)) {
          allItems.add(NativeEventFeedItem(event));
          existingIds.add(event.id);
        }
      }
    }

    // Compute filtered events (works on FeedItem)
    final filteredFeed = _filterFeed(
      allItems,
      selectedCategories,
      selectedCity,
      selectedTags,
      _searchQuery,
    );

    // Use discovery state for loading flags; fall back to eventsState for cities
    final isLoading = discoveryState.isLoading;

    // Compute available cities from both sources
    final availableCities = [
      ...discoveryState.events.map((e) => e.city),
      ...eventsState.events.map((e) => e.city),
    ].whereType<String>().toSet().toList()
      ..sort();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.read(discoveryFeedProvider.notifier).refresh(),
              ref.read(externalEventsProvider.notifier).refresh(),
            ]);
          },
          child: CustomScrollView(
            slivers: [
              _Header(),
              if (isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (eventsState.isUsingPlaceholders && discoveryState.events.isEmpty)
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
                              L.tr('showing_sample_events'),
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
                  child: _ScoredCarouselSection(),
                ),
                _SectionHeader(title: L.tr('events_home_upcoming')),
                SliverToBoxAdapter(
                  child: EventFilterChips(
                    selectedCategories: selectedCategories,
                    selectedCity: selectedCity,
                    selectedTags: selectedTags,
                    availableCities: availableCities,
                    isSearching: _isSearching,
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    onSearchChanged: _onSearchChanged,
                    onSearchToggled: _toggleSearch,
                    onCategoriesChanged: (categories) {
                      ref.read(_selectedCategoriesProvider.notifier).state = categories;
                    },
                    onCityChanged: (city) {
                      ref.read(_selectedCityProvider.notifier).state = city;
                    },
                    onTagsChanged: (tags) {
                      ref.read(_selectedTagsProvider.notifier).state = tags;
                    },
                  ),
                ),
                // Invite code result card
                if (_inviteCodeResult != null)
                  SliverToBoxAdapter(
                    child: _InviteCodeResultCard(
                      event: _inviteCodeResult!,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EventDetailsScreen(event: _inviteCodeResult!),
                          ),
                        );
                      },
                    ),
                  ),
                if (filteredFeed.isEmpty && _inviteCodeResult == null)
                  _EmptyFilterState(
                    searchQuery: _searchQuery,
                    onClearFilters: () {
                      ref.read(_selectedCategoriesProvider.notifier).state = {};
                      ref.read(_selectedCityProvider.notifier).state = null;
                      ref.read(_selectedTagsProvider.notifier).state = {};
                      if (_isSearching) _toggleSearch();
                    },
                  )
                else if (filteredFeed.isNotEmpty)
                  _MixedFeedList(items: filteredFeed),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Filter mixed feed items by category, city, tags, and search query.
  List<FeedItem> _filterFeed(
    List<FeedItem> items,
    Set<EventCategory> categories,
    String? city,
    Set<String> tags,
    String searchQuery,
  ) {
    return items.where((item) {
      switch (item) {
        case NativeEventFeedItem(:final event):
          // Category filter
          if (categories.isNotEmpty) {
            final eventCategory = event.eventCategory;
            if (eventCategory == null || !categories.contains(eventCategory)) return false;
          }
          if (city != null && event.city != city) return false;
          if (tags.isNotEmpty && !tags.every((t) => event.tags.contains(t))) return false;
          if (searchQuery.isNotEmpty) {
            final match = event.title.toLowerCase().contains(searchQuery) ||
                event.subtitle.toLowerCase().contains(searchQuery) ||
                (event.venue?.toLowerCase().contains(searchQuery) ?? false) ||
                (event.city?.toLowerCase().contains(searchQuery) ?? false);
            if (!match) return false;
          }
          return true;

        case ExternalEventFeedItem(:final event):
          // Category filter (map EventCategory name to external category string)
          if (categories.isNotEmpty) {
            final cat = event.category?.toLowerCase();
            final match = categories.any((c) => c.label.toLowerCase() == cat);
            if (!match) return false;
          }
          // City filter — external events use venueAddress
          if (city != null) {
            final addr = event.venueAddress?.toLowerCase() ?? '';
            if (!addr.contains(city.toLowerCase())) return false;
          }
          // Tags don't apply to external events — skip
          if (tags.isNotEmpty) return false;
          // Search filter
          if (searchQuery.isNotEmpty) {
            final match = event.title.toLowerCase().contains(searchQuery) ||
                (event.venueName?.toLowerCase().contains(searchQuery) ?? false) ||
                (event.venueAddress?.toLowerCase().contains(searchQuery) ?? false);
            if (!match) return false;
          }
          return true;
      }
    }).toList();
  }
}

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUseVenues = TierLimits.canUseVenueBuilder(
      ref.watch(subscriptionProvider).effectiveTier,
    );

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
            if (canUseVenues) ...[
              const SizedBox(width: 10),
              GradientVenuesButton(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const VenuesScreen()),
                  );
                },
              ),
            ],
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
            L.tr('events_home_featured'),
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

/// Featured carousel powered by discovery scores.
/// Shows hand-pinned events first, then top-scored events.
/// Falls back to chronological if the RPC is unavailable.
class _ScoredCarouselSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featuredAsync = ref.watch(discoveryFeaturedProvider);
    final fallbackEvents = ref.watch(eventsProvider).featuredEvents;

    final events = featuredAsync.when(
      data: (scored) => scored.isNotEmpty ? scored : fallbackEvents,
      loading: () => fallbackEvents,
      error: (_, __) => fallbackEvents,
    );

    return _CarouselSection(events: events);
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

class _EventList extends ConsumerStatefulWidget {
  final List<EventModel> events;

  const _EventList({required this.events});

  @override
  ConsumerState<_EventList> createState() => _EventListState();
}

class _EventListState extends ConsumerState<_EventList> {
  @override
  Widget build(BuildContext context) {
    final isLoadingMore = ref.watch(eventsLoadingMoreProvider);
    final canLoadMore = ref.watch(eventsCanLoadMoreProvider);

    // Total items: events + optional loading indicator
    final itemCount = widget.events.length + (isLoadingMore || canLoadMore ? 1 : 0);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // If this is the last item and we can load more, trigger load
          if (index == widget.events.length) {
            // Show loading indicator or trigger load more
            if (isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            // Trigger load more when this item becomes visible
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(eventsProvider.notifier).loadMore();
            });
            return const SizedBox(height: 16);
          }

          // Check if we're near the end and should preload
          if (index >= widget.events.length - 3 && canLoadMore && !isLoadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(eventsProvider.notifier).loadMore();
            });
          }

          return _EventListTile(event: widget.events[index]);
        },
        childCount: itemCount,
      ),
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  final String searchQuery;
  final VoidCallback onClearFilters;

  const _EmptyFilterState({
    required this.searchQuery,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasSearch = searchQuery.isNotEmpty;

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
                L.tr('events_home_no_events'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasSearch
                    ? L.tr('no_events_match_filter')
                    : L.tr('try_different_search_or_filter'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: Text(hasSearch ? 'Clear Search & Filters' : L.tr('events_home_clear_filters')),
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
          if (event.getDisplayLocation(hasTicket: false) != null)
            Text(
              event.getDisplayLocation(hasTicket: false)!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (event.autoBadges.isNotEmpty || event.eventTags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                ...event.autoBadges.take(1).map((badge) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: badge.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badge.icon, size: 10, color: badge.color),
                        const SizedBox(width: 2),
                        Text(
                          badge.label,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: badge.color,
                            fontWeight: FontWeight.w600,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
                ...event.eventTags.take(2).map((tag) {
                  final tagColor = tag.color ?? Theme.of(context).colorScheme.primary;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: tagColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tag.label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tagColor,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
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

class _MixedFeedList extends ConsumerStatefulWidget {
  final List<FeedItem> items;

  const _MixedFeedList({required this.items});

  @override
  ConsumerState<_MixedFeedList> createState() => _MixedFeedListState();
}

class _MixedFeedListState extends ConsumerState<_MixedFeedList> {
  @override
  Widget build(BuildContext context) {
    final isLoadingMore = ref.watch(discoveryLoadingMoreProvider);
    final canLoadMore = ref.watch(discoveryCanLoadMoreProvider);
    final itemCount = widget.items.length + (isLoadingMore || canLoadMore ? 1 : 0);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == widget.items.length) {
            if (isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(discoveryFeedProvider.notifier).loadMore();
              ref.read(externalEventsProvider.notifier).loadMore();
            });
            return const SizedBox(height: 16);
          }

          if (index >= widget.items.length - 3 && canLoadMore && !isLoadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(discoveryFeedProvider.notifier).loadMore();
              ref.read(externalEventsProvider.notifier).loadMore();
            });
          }

          final item = widget.items[index];
          return switch (item) {
            NativeEventFeedItem(:final event) => _EventListTile(event: event),
            ExternalEventFeedItem(:final event) => _ExternalEventListTile(event: event),
          };
        },
        childCount: itemCount,
      ),
    );
  }
}

class _ExternalEventListTile extends StatelessWidget {
  final ExternalEvent event;

  const _ExternalEventListTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final sourceColor = switch (event.source) {
      'ticketmaster' => const Color(0xFF026CDF),
      'seatgeek' => const Color(0xFFF05537),
      _ => colorScheme.primary,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: _ExternalThumbnail(imageUrl: event.imageUrl),
      title: Text(
        event.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            _formatDate(event.startDate),
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.primary),
          ),
          if (event.displayLocation.isNotEmpty)
            Text(
              event.displayLocation,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: sourceColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'via ${event.sourceLabel}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: sourceColor,
                fontWeight: FontWeight.w600,
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
      trailing: event.formattedPrice.isNotEmpty
          ? Text(
              event.formattedPrice,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ExternalEventDetailScreen(event: event),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    final diff = date.difference(now).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _ExternalThumbnail extends StatelessWidget {
  final String? imageUrl;

  const _ExternalThumbnail({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(context),
        ),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.event, color: Colors.white, size: 24),
    );
  }
}

class _InviteCodeResultCard extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;

  const _InviteCodeResultCard({
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = event.getNoiseConfig();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Container(
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: config.colors,
                    ),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_outline, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Private Event Found',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              event.subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
