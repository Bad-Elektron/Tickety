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
import '../models/event_model.dart';
import '../widgets/widgets.dart';
import 'event_details_screen.dart';
import 'my_events_screen.dart';

/// Section definition for Netflix-style rows.
class _FeedSection {
  final String title;
  final IconData icon;
  final Color color;
  final List<EventModel> events;

  const _FeedSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.events,
  });
}

/// The main home screen with Netflix-style discovery rows.
///
/// Default view: Featured carousel + horizontal rows grouped by tag/vibe.
/// Search view: Flat filtered list with filter chips.
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

  /// Build Netflix-style sections from the event feed, grouped by tags.
  List<_FeedSection> _buildSections(List<EventModel> events) {
    if (events.isEmpty) return [];

    final sections = <_FeedSection>[];

    // ── Computed sections ──

    // "New This Week" — events created within 7 days
    final newEvents = events.where((e) {
      if (e.createdAt == null) return false;
      return DateTime.now().difference(e.createdAt!).inDays <= 7;
    }).toList();
    if (newEvents.length >= 2) {
      sections.add(_FeedSection(
        title: L.tr('New This Week'),
        icon: Icons.new_releases,
        color: const Color(0xFF3B82F6),
        events: newEvents,
      ));
    }

    // "Free Events"
    final freeEvents = events.where((e) => e.isFree).toList();
    if (freeEvents.length >= 2) {
      sections.add(_FeedSection(
        title: L.tr('Free Events'),
        icon: Icons.money_off,
        color: const Color(0xFF14B8A6),
        events: freeEvents,
      ));
    }

    // ── Tag-based sections ──
    // Define which tags get their own rows, with display config
    const tagSections = <(List<String>, String, IconData, Color)>[
      (['live_music'], 'Live Music', Icons.music_note, Color(0xFFEC4899)),
      (['dj', 'nightlife'], 'Nightlife & DJs', Icons.nightlife, Color(0xFF7C3AED)),
      (['outdoor'], 'Outdoor', Icons.park, Color(0xFF22C55E)),
      (['food', 'drinks'], 'Food & Drinks', Icons.restaurant, Color(0xFFF97316)),
      (['art', 'theater'], 'Arts & Culture', Icons.palette, Color(0xFFE11D48)),
      (['sports'], 'Sports', Icons.sports, Color(0xFF16A34A)),
      (['comedy'], 'Comedy', Icons.sentiment_very_satisfied, Color(0xFFFBBF24)),
      (['networking'], 'Networking', Icons.people, Color(0xFF0EA5E9)),
      (['workshop'], 'Workshops', Icons.construction, Color(0xFF84CC16)),
      (['family_friendly'], 'Family Friendly', Icons.family_restroom, Color(0xFF06B6D4)),
      (['tech'], 'Tech', Icons.computer, Color(0xFF3B82F6)),
      (['wellness'], 'Wellness', Icons.spa, Color(0xFF2DD4BF)),
      // Vibe tags
      (['exclusive'], 'Exclusive', Icons.diamond, Color(0xFF8B5CF6)),
      (['high_energy'], 'High Energy', Icons.bolt, Color(0xFFEF4444)),
      (['chill'], 'Chill Vibes', Icons.waves, Color(0xFF06B6D4)),
      (['immersive'], 'Immersive', Icons.vrpano, Color(0xFF7C3AED)),
      (['underground'], 'Underground', Icons.subway, Color(0xFF6B7280)),
    ];

    for (final (tagIds, title, icon, color) in tagSections) {
      final matching = events.where((e) =>
        tagIds.any((tagId) => e.tags.contains(tagId)),
      ).toList();

      if (matching.length >= 2) {
        sections.add(_FeedSection(
          title: L.tr(title),
          icon: icon,
          color: color,
          events: matching,
        ));
      }
    }

    // ── Category-based fallback sections ──
    // For events that may not have tags but have a category set
    const categorySections = <(String, String, IconData, Color)>[
      ('Music', 'Music', Icons.music_note, Color(0xFFEC4899)),
      ('Entertainment', 'Entertainment', Icons.celebration, Color(0xFFF59E0B)),
      ('Business', 'Business', Icons.business_center, Color(0xFF64748B)),
    ];

    final tagCoveredIds = sections.expand((s) => s.events.map((e) => e.id)).toSet();

    for (final (category, title, icon, color) in categorySections) {
      final matching = events.where((e) {
        if (tagCoveredIds.contains(e.id)) return false;
        return e.category?.toLowerCase() == category.toLowerCase();
      }).toList();

      if (matching.length >= 2) {
        sections.add(_FeedSection(
          title: L.tr(title),
          icon: icon,
          color: color,
          events: matching,
        ));
      }
    }

    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final discoveryState = ref.watch(discoveryFeedProvider);
    final eventsState = ref.watch(eventsProvider);
    final externalState = ref.watch(externalEventsProvider);
    final isLoading = discoveryState.isLoading;

    // All native events for section building
    final nativeEvents = discoveryState.events;

    // Build mixed feed for search mode
    final nativeItems = nativeEvents.map(NativeEventFeedItem.new).toList();
    final externalItems = externalState.events.map(ExternalEventFeedItem.new).toList();
    final allItems = [...nativeItems, ...externalItems];

    // Merge server search results when searching
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

    final isSearchActive = _isSearching || _searchQuery.isNotEmpty;

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
              const _Header(),
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

                // Featured carousel — always visible
                SliverToBoxAdapter(
                  child: _ScoredCarouselSection(),
                ),

                // ── Search mode or discovery mode ──
                ..._buildDiscoverySections(nativeEvents),

                if (isSearchActive) ...[
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
                  if (_isServerSearching)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else ...[
                    ..._buildSearchResults(allItems),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build the Netflix-style discovery sections as slivers.
  List<Widget> _buildDiscoverySections(List<EventModel> events) {
    final sections = _buildSections(events);
    final slivers = <Widget>[];

    // Tag/vibe rows
    for (final section in sections) {
      slivers.add(SliverToBoxAdapter(
        child: _HorizontalEventRow(
          title: section.title,
          icon: section.icon,
          color: section.color,
          events: section.events,
        ),
      ));
    }

    // "Upcoming Events" + search bar — after tag rows
    slivers.add(SliverToBoxAdapter(
      child: _SearchBar(
        isSearching: _isSearching,
        searchController: _searchController,
        searchFocusNode: _searchFocusNode,
        onSearchChanged: _onSearchChanged,
        onSearchToggled: _toggleSearch,
      ),
    ));

    // All events list (only in discovery mode, not search mode)
    if (!_isSearching && !_searchQuery.isNotEmpty) {
      slivers.add(_MixedFeedList(
        items: events.map(NativeEventFeedItem.new).toList(),
      ));
    }

    return slivers;
  }

  /// Build search results as slivers.
  List<Widget> _buildSearchResults(List<FeedItem> allItems) {
    final filtered = _filterFeedBySearch(allItems, _searchQuery);

    if (filtered.isEmpty && _inviteCodeResult == null) {
      return [
        _EmptyFilterState(
          searchQuery: _searchQuery,
          onClearFilters: () {
            if (_isSearching) _toggleSearch();
          },
        ),
      ];
    }

    if (filtered.isNotEmpty) {
      return [_MixedFeedList(items: filtered)];
    }

    return [];
  }

  /// Simple search-only filter (no category/city/tag chips in search mode).
  List<FeedItem> _filterFeedBySearch(List<FeedItem> items, String query) {
    if (query.isEmpty) return items;
    return items.where((item) {
      switch (item) {
        case NativeEventFeedItem(:final event):
          return event.title.toLowerCase().contains(query) ||
              event.subtitle.toLowerCase().contains(query) ||
              (event.venue?.toLowerCase().contains(query) ?? false) ||
              (event.city?.toLowerCase().contains(query) ?? false);
        case ExternalEventFeedItem(:final event):
          return event.title.toLowerCase().contains(query) ||
              (event.venueName?.toLowerCase().contains(query) ?? false) ||
              (event.venueAddress?.toLowerCase().contains(query) ?? false);
      }
    }).toList();
  }
}

/// Header with profile buttons.
class _Header extends ConsumerWidget {
  const _Header();

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

/// Search bar with "Upcoming Events" label and search icon toggle.
class _SearchBar extends StatelessWidget {
  final bool isSearching;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchToggled;

  const _SearchBar({
    required this.isSearching,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onSearchToggled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          // Title — always visible
          Text(
            L.tr('events_home_upcoming'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          // Search field — expands to the right of the title
          if (isSearching)
            Expanded(
              child: TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                autofocus: true,
                onChanged: onSearchChanged,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  hintText: L.tr('Search...'),
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),
          // Search / close icon
          GestureDetector(
            onTap: onSearchToggled,
            child: Icon(
              isSearching ? Icons.close : Icons.search,
              size: 20,
              color: isSearching
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal scrollable row of event cards, Netflix-style.
class _HorizontalEventRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<EventModel> events;

  const _HorizontalEventRow({
    required this.title,
    required this.icon,
    required this.color,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        // Horizontal scrollable cards
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: events.length.clamp(0, 10),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return _EventCard(event: events[index]);
            },
          ),
        ),
      ],
    );
  }
}

/// Compact event card for horizontal rows.
class _EventCard extends StatelessWidget {
  final EventModel event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = event.getNoiseConfig();

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailsScreen(event: event),
          ),
        );
      },
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event thumbnail
            Container(
              height: 110,
              width: 150,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: config.colors,
                ),
              ),
              child: Stack(
                children: [
                  // Price badge
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        event.formattedPrice,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  // Auto badge
                  if (event.autoBadges.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: event.autoBadges.first.color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(event.autoBadges.first.icon, size: 10, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              event.autoBadges.first.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            // Date & location
            Text(
              _formatDate(event.date),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontSize: 11,
              ),
            ),
            if (event.getDisplayLocation(hasTicket: false) != null)
              Text(
                event.getDisplayLocation(hasTicket: false)!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
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

class _CarouselSection extends StatelessWidget {
  final List<EventModel> events;

  const _CarouselSection({required this.events});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                L.tr('no_events_match_filter'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: Text(L.tr('events_home_clear_filters')),
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
