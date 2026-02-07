import 'dart:async';

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
/// Uses Riverpod for created events with server-side filtering.
class MyEventsScreen extends ConsumerStatefulWidget {
  const MyEventsScreen({super.key});

  @override
  ConsumerState<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends ConsumerState<MyEventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  bool _isSearching = false;

  final _staffRepository = StaffRepository();

  List<_StaffEventData> _usheringEvents = [];
  List<_StaffEventData> _sellingEvents = [];
  List<_StaffEventData> _filteredUsheringEvents = [];
  List<_StaffEventData> _filteredSellingEvents = [];

  bool _isLoadingStaff = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadStaffEvents();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Handle search input with debounce for server-side search.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      // Update server-side search for Created tab
      ref.read(myEventsProvider.notifier).setSearchQuery(value);
      // Update client-side filter for staff tabs
      _filterStaffEvents();
    });
  }

  /// Handle date filter change.
  void _onDateFilterChanged(MyEventsDateFilter filter) {
    // Update server-side filter for Created tab
    ref.read(myEventsProvider.notifier).setDateFilter(filter);
    // Update client-side filter for staff tabs
    _filterStaffEvents();
  }

  /// Clear all filters.
  void _clearFilters() {
    _searchController.clear();
    ref.read(myEventsProvider.notifier).clearFilters();
    _filterStaffEvents();
  }

  /// Filter staff events client-side (ushering/selling tabs).
  void _filterStaffEvents() {
    final state = ref.read(myEventsProvider);
    final searchQuery = _searchController.text.trim().toLowerCase();
    final dateFilter = state.dateFilter;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final oneWeekAgo = today.subtract(const Duration(days: 7));

    bool matchesFilters(_StaffEventData data) {
      final event = data.event;

      // Search filter
      if (searchQuery.isNotEmpty) {
        final matchesSearch = event.title.toLowerCase().contains(searchQuery) ||
            event.subtitle.toLowerCase().contains(searchQuery) ||
            (event.venue?.toLowerCase().contains(searchQuery) ?? false) ||
            (event.city?.toLowerCase().contains(searchQuery) ?? false);
        if (!matchesSearch) return false;
      }

      // Date filter
      final eventDay = DateTime(event.date.year, event.date.month, event.date.day);
      final isUpcoming = eventDay.compareTo(today) >= 0;
      final isWithinPastWeek = eventDay.compareTo(oneWeekAgo) >= 0 && eventDay.compareTo(today) < 0;

      return switch (dateFilter) {
        MyEventsDateFilter.recent => isUpcoming || isWithinPastWeek,
        MyEventsDateFilter.upcoming => isUpcoming,
        MyEventsDateFilter.all => true,
        MyEventsDateFilter.past => !isUpcoming,
      };
    }

    // Sort function: upcoming first (soonest), then past (most recent)
    int sortByDate(_StaffEventData a, _StaffEventData b) {
      final aDay = DateTime(a.event.date.year, a.event.date.month, a.event.date.day);
      final bDay = DateTime(b.event.date.year, b.event.date.month, b.event.date.day);
      final aIsUpcoming = aDay.compareTo(today) >= 0;
      final bIsUpcoming = bDay.compareTo(today) >= 0;

      if (aIsUpcoming && !bIsUpcoming) return -1;
      if (!aIsUpcoming && bIsUpcoming) return 1;

      return aIsUpcoming ? aDay.compareTo(bDay) : bDay.compareTo(aDay);
    }

    setState(() {
      _filteredUsheringEvents = _usheringEvents.where(matchesFilters).toList()..sort(sortByDate);
      _filteredSellingEvents = _sellingEvents.where(matchesFilters).toList()..sort(sortByDate);
    });
  }

  Future<void> _loadStaffEvents() async {
    if (!SupabaseService.instance.isAuthenticated) {
      setState(() {
        _usheringEvents = [];
        _sellingEvents = [];
        _filteredUsheringEvents = [];
        _filteredSellingEvents = [];
        _isLoadingStaff = false;
      });
      return;
    }

    try {
      final staffResult = await _staffRepository.getMyStaffEvents();
      final ushering = <_StaffEventData>[];
      final selling = <_StaffEventData>[];

      for (final assignment in staffResult.items) {
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
        // Apply initial filters
        _filterStaffEvents();
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

    // Watch my events state from Riverpod - server-side filtering!
    final myEventsState = ref.watch(myEventsProvider);

    final filterLabels = {
      MyEventsDateFilter.recent: 'Recent',
      MyEventsDateFilter.upcoming: 'Upcoming',
      MyEventsDateFilter.all: 'All',
      MyEventsDateFilter.past: 'Past',
    };

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                autofocus: true,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Search events...',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  border: InputBorder.none,
                ),
              )
            : const Text('My Events'),
        centerTitle: !_isSearching,
        actions: [
          // Search toggle
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  _searchFocusNode.unfocus();
                  _onSearchChanged('');
                }
                _isSearching = !_isSearching;
              });
            },
          ),
          // Filter popup
          PopupMenuButton<MyEventsDateFilter>(
            icon: Icon(
              Icons.filter_list,
              color: myEventsState.dateFilter != MyEventsDateFilter.recent
                  ? colorScheme.primary
                  : null,
            ),
            onSelected: _onDateFilterChanged,
            itemBuilder: (_) => MyEventsDateFilter.values.map((filter) {
              final isSelected = myEventsState.dateFilter == filter;
              return PopupMenuItem(
                value: filter,
                child: Row(
                  children: [
                    if (isSelected)
                      Icon(Icons.check, size: 18, color: colorScheme.primary)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 12),
                    Text(filterLabels[filter]!),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
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
          // Created events tab - server-side filtering via Riverpod
          _buildCreatedEventsTab(
            theme: theme,
            colorScheme: colorScheme,
            state: myEventsState,
          ),
          // Ushering events tab - client-side filtering (small dataset)
          _buildUsheringEventsTab(
            theme: theme,
            colorScheme: colorScheme,
            state: myEventsState,
          ),
          // Selling events tab - client-side filtering (small dataset)
          _buildSellingEventsTab(
            theme: theme,
            colorScheme: colorScheme,
            state: myEventsState,
          ),
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

  Widget _buildCreatedEventsTab({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required MyEventsState state,
  }) {
    // Show empty state only if no filters are applied and no events
    final hasFilters = state.searchQuery != null || state.dateFilter != MyEventsDateFilter.recent;

    if (state.isLoading && state.events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // No events at all (without filters)
    if (state.events.isEmpty && !hasFilters && !state.isLoading) {
      return _buildEmptyCreatedState(theme, colorScheme);
    }

    if (state.events.isEmpty) {
      return _buildNoFilterResults(theme, colorScheme);
    }

    return _buildCreatedEventsList(state);
  }

  Widget _buildNoFilterResults(ThemeData theme, ColorScheme colorScheme) {
    final hasSearch = _searchController.text.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No matching events',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Try a different search term or filter.'
                  : 'No events match the selected filter.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear filters'),
            ),
          ],
        ),
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

  Widget _buildUsheringEventsTab({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required MyEventsState state,
  }) {
    if (_isLoadingStaff) {
      return const Center(child: CircularProgressIndicator());
    }

    // No events at all - still allow pull-to-refresh
    if (_usheringEvents.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadStaffEvents,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              child: _buildEmptyUsheringState(theme, colorScheme),
            ),
          ],
        ),
      );
    }

    if (_filteredUsheringEvents.isEmpty) {
      return _buildNoFilterResults(theme, colorScheme);
    }

    return _buildUsheringEventsList(_filteredUsheringEvents);
  }

  Widget _buildSellingEventsTab({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required MyEventsState state,
  }) {
    if (_isLoadingStaff) {
      return const Center(child: CircularProgressIndicator());
    }

    // No events at all - still allow pull-to-refresh
    if (_sellingEvents.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadStaffEvents,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              child: _buildEmptySellingState(theme, colorScheme),
            ),
          ],
        ),
      );
    }

    if (_filteredSellingEvents.isEmpty) {
      return _buildNoFilterResults(theme, colorScheme);
    }

    return _buildSellingEventsList(_filteredSellingEvents);
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

  Widget _buildCreatedEventsList(MyEventsState state) {
    return RefreshIndicator(
      onRefresh: () => ref.read(myEventsProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: state.events.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Show "Load more" button at the end
          if (index == state.events.length) {
            return _buildLoadMoreButton(
              isLoading: state.isLoadingMore,
              onPressed: () => ref.read(myEventsProvider.notifier).loadMore(),
            );
          }

          final event = state.events[index];
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

  Widget _buildLoadMoreButton({required bool isLoading, required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.expand_more),
              label: const Text('Load more'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
    );
  }

  Widget _buildUsheringEventsList(List<_StaffEventData> events) {
    // Staff events are typically small datasets, no pagination needed
    return RefreshIndicator(
      onRefresh: _loadStaffEvents,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final data = events[index];
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
      ),
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

  Widget _buildSellingEventsList(List<_StaffEventData> events) {
    // Staff events are typically small datasets, no pagination needed
    return RefreshIndicator(
      onRefresh: _loadStaffEvents,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final data = events[index];
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
      ),
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

class _MyEventCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = event.getNoiseConfig();
    final soldCountAsync = ref.watch(ticketSoldCountProvider(event.id));

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
                          label: soldCountAsync.when(
                            data: (count) => '$count sold',
                            loading: () => '... sold',
                            error: (_, __) => '-- sold',
                          ),
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        _StatChip(
                          icon: Icons.calendar_today_outlined,
                          label: _formatDate(event.date),
                          color: _isEventPast(event.date)
                              ? colorScheme.error
                              : (badgeColor ?? colorScheme.tertiary),
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

  bool _isEventPast(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    return eventDay.isBefore(today);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    final diff = eventDay.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff < -1) {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return 'Ended · ${months[date.month - 1]} ${date.day}';
    }
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
