import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/events/data/data.dart';
import '../../features/events/models/event_model.dart';
import '../../features/events/models/ticket_availability.dart';
import '../errors/errors.dart';
import 'auth_provider.dart';

export '../../features/events/data/data.dart' show MyEventsDateFilter;

const _tag = 'EventsProvider';

/// Default page size for events pagination.
const int kEventsPageSize = 20;

/// State for the events list.
class EventsState {
  final List<EventModel> events;
  final List<EventModel> featuredEvents;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final bool isUsingPlaceholders;
  final int currentPage;
  final bool hasMore;
  final int pageSize;

  const EventsState({
    this.events = const [],
    this.featuredEvents = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.isUsingPlaceholders = false,
    this.currentPage = 0,
    this.hasMore = true,
    this.pageSize = kEventsPageSize,
  });

  /// Whether more events can be loaded.
  bool get canLoadMore => hasMore && !isLoading && !isLoadingMore;

  EventsState copyWith({
    List<EventModel>? events,
    List<EventModel>? featuredEvents,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool? isUsingPlaceholders,
    int? currentPage,
    bool? hasMore,
    int? pageSize,
    bool clearError = false,
  }) {
    return EventsState(
      events: events ?? this.events,
      featuredEvents: featuredEvents ?? this.featuredEvents,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      isUsingPlaceholders: isUsingPlaceholders ?? this.isUsingPlaceholders,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}

/// Notifier that manages events data.
class EventsNotifier extends StateNotifier<EventsState> {
  final EventRepository _repository;

  EventsNotifier(this._repository) : super(const EventsState()) {
    loadEvents();
  }

  /// Load the first page of upcoming events.
  Future<void> loadEvents() async {
    AppLogger.debug('Loading upcoming events', tag: _tag);
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentPage: 0,
      hasMore: true,
    );

    try {
      final result = await _repository.getUpcomingEvents(
        page: 0,
        pageSize: state.pageSize,
      );
      final featured = await _repository.getFeaturedEvents(limit: 5);

      AppLogger.info(
        'Loaded ${result.items.length} events (${featured.length} featured, hasMore: ${result.hasMore})',
        tag: _tag,
      );

      state = state.copyWith(
        events: result.items,
        featuredEvents: featured,
        isLoading: false,
        isUsingPlaceholders: false,
        currentPage: 0,
        hasMore: result.hasMore,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load events, falling back to placeholders',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      // Fall back to placeholders on error
      state = state.copyWith(
        events: PlaceholderEvents.upcoming,
        featuredEvents: PlaceholderEvents.featured,
        isLoading: false,
        error: appError.userMessage,
        isUsingPlaceholders: true,
        hasMore: false,
      );
    }
  }

  /// Load more events (next page).
  Future<void> loadMore() async {
    if (!state.canLoadMore) {
      AppLogger.debug('Cannot load more: canLoadMore=${state.canLoadMore}', tag: _tag);
      return;
    }

    final nextPage = state.currentPage + 1;
    AppLogger.debug('Loading more events (page: $nextPage)', tag: _tag);
    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _repository.getUpcomingEvents(
        page: nextPage,
        pageSize: state.pageSize,
      );

      AppLogger.info(
        'Loaded ${result.items.length} more events (hasMore: ${result.hasMore})',
        tag: _tag,
      );

      state = state.copyWith(
        events: [...state.events, ...result.items],
        isLoadingMore: false,
        currentPage: nextPage,
        hasMore: result.hasMore,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load more events',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      // Keep existing data on error, just stop loading
      state = state.copyWith(
        isLoadingMore: false,
        error: appError.userMessage,
      );
    }
  }

  /// Refresh events (pull-to-refresh).
  Future<void> refresh() {
    AppLogger.debug('Refreshing events', tag: _tag);
    return loadEvents();
  }

  /// Filter events by category.
  List<EventModel> filterByCategory(String? category) {
    if (category == null) return state.events;
    return state.events.where((e) => e.category == category).toList();
  }

  /// Filter events by city.
  List<EventModel> filterByCity(String? city) {
    if (city == null) return state.events;
    return state.events.where((e) => e.city == city).toList();
  }

  /// Get event by ID.
  EventModel? getEventById(String id) {
    try {
      return state.events.firstWhere((e) => e.id == id);
    } catch (_) {
      AppLogger.debug('Event not found in state: $id', tag: _tag);
      return null;
    }
  }
}

/// Repository provider - can be overridden for testing.
final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return SupabaseEventRepository();
});

/// Main events provider.
final eventsProvider = StateNotifierProvider<EventsNotifier, EventsState>((ref) {
  final repository = ref.watch(eventRepositoryProvider);
  return EventsNotifier(repository);
});

/// Convenience provider for featured events only.
final featuredEventsProvider = Provider<List<EventModel>>((ref) {
  return ref.watch(eventsProvider).featuredEvents;
});

/// Convenience provider for loading state.
final eventsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(eventsProvider).isLoading;
});

/// Convenience provider for load more state.
final eventsLoadingMoreProvider = Provider<bool>((ref) {
  return ref.watch(eventsProvider).isLoadingMore;
});

/// Convenience provider for can load more state.
final eventsCanLoadMoreProvider = Provider<bool>((ref) {
  return ref.watch(eventsProvider).canLoadMore;
});

// ============================================================
// MY EVENTS (User's created events)
// ============================================================

/// Default page size for user's events.
const int kMyEventsPageSize = 15;

/// State for user's created events.
class MyEventsState {
  final List<EventModel> events;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int currentPage;
  final bool hasMore;
  final int pageSize;
  final MyEventsDateFilter dateFilter;
  final String? searchQuery;

  const MyEventsState({
    this.events = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.currentPage = 0,
    this.hasMore = true,
    this.pageSize = kMyEventsPageSize,
    this.dateFilter = MyEventsDateFilter.recent,
    this.searchQuery,
  });

  /// Whether more events can be loaded.
  bool get canLoadMore => hasMore && !isLoading && !isLoadingMore;

  MyEventsState copyWith({
    List<EventModel>? events,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    int? currentPage,
    bool? hasMore,
    int? pageSize,
    MyEventsDateFilter? dateFilter,
    String? searchQuery,
    bool clearError = false,
    bool clearSearch = false,
  }) {
    return MyEventsState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      pageSize: pageSize ?? this.pageSize,
      dateFilter: dateFilter ?? this.dateFilter,
      searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
    );
  }
}

/// Notifier for user's created events.
class MyEventsNotifier extends StateNotifier<MyEventsState> {
  final EventRepository _repository;
  final bool _isAuthenticated;

  MyEventsNotifier(this._repository, this._isAuthenticated)
      : super(const MyEventsState()) {
    if (_isAuthenticated) {
      loadMyEvents();
    }
  }

  /// Load the first page of events created by the current user.
  Future<void> loadMyEvents() async {
    if (!_isAuthenticated) {
      AppLogger.debug('Not authenticated, skipping my events load', tag: _tag);
      state = state.copyWith(events: [], isLoading: false, hasMore: false);
      return;
    }

    AppLogger.debug(
      'Loading user\'s events (filter: ${state.dateFilter}, search: ${state.searchQuery})',
      tag: _tag,
    );
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentPage: 0,
      hasMore: true,
    );

    try {
      final result = await _repository.getMyEvents(
        dateFilter: state.dateFilter,
        searchQuery: state.searchQuery,
        page: 0,
        pageSize: state.pageSize,
      );
      AppLogger.info(
        'Loaded ${result.items.length} user events (hasMore: ${result.hasMore})',
        tag: _tag,
      );
      state = state.copyWith(
        events: result.items,
        isLoading: false,
        currentPage: 0,
        hasMore: result.hasMore,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load user events',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
        hasMore: false,
      );
    }
  }

  /// Load more events (next page).
  Future<void> loadMore() async {
    if (!_isAuthenticated || !state.canLoadMore) {
      AppLogger.debug(
        'Cannot load more events: authenticated=$_isAuthenticated, canLoadMore=${state.canLoadMore}',
        tag: _tag,
      );
      return;
    }

    final nextPage = state.currentPage + 1;
    AppLogger.debug('Loading more events (page: $nextPage)', tag: _tag);
    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _repository.getMyEvents(
        dateFilter: state.dateFilter,
        searchQuery: state.searchQuery,
        page: nextPage,
        pageSize: state.pageSize,
      );

      AppLogger.info(
        'Loaded ${result.items.length} more events (hasMore: ${result.hasMore})',
        tag: _tag,
      );

      state = state.copyWith(
        events: [...state.events, ...result.items],
        isLoadingMore: false,
        currentPage: nextPage,
        hasMore: result.hasMore,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load more events',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoadingMore: false,
        error: appError.userMessage,
      );
    }
  }

  /// Update the date filter and reload events.
  Future<void> setDateFilter(MyEventsDateFilter filter) async {
    if (state.dateFilter == filter) return;
    AppLogger.debug('Setting date filter: $filter', tag: _tag);
    state = state.copyWith(dateFilter: filter);
    await loadMyEvents();
  }

  /// Update the search query and reload events.
  Future<void> setSearchQuery(String? query) async {
    final normalizedQuery = query?.trim().isEmpty == true ? null : query?.trim();
    if (state.searchQuery == normalizedQuery) return;
    AppLogger.debug('Setting search query: $normalizedQuery', tag: _tag);
    state = state.copyWith(searchQuery: normalizedQuery);
    await loadMyEvents();
  }

  /// Clear all filters and reload.
  Future<void> clearFilters() async {
    AppLogger.debug('Clearing filters', tag: _tag);
    state = state.copyWith(
      dateFilter: MyEventsDateFilter.recent,
      clearSearch: true,
    );
    await loadMyEvents();
  }

  /// Refresh events (reload first page with current filters).
  Future<void> refresh() {
    AppLogger.debug('Refreshing user events', tag: _tag);
    return loadMyEvents();
  }

  /// Add a newly created event to the list.
  void addEvent(EventModel event) {
    AppLogger.debug('Adding event to local state: ${event.title}', tag: _tag);
    state = state.copyWith(events: [event, ...state.events]);
  }
}

/// Provider for user's created events - rebuilds when auth changes.
final myEventsProvider =
    StateNotifierProvider<MyEventsNotifier, MyEventsState>((ref) {
  final repository = ref.watch(eventRepositoryProvider);
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  return MyEventsNotifier(repository, isAuthenticated);
});

// ============================================================
// TICKET AVAILABILITY
// ============================================================

/// Provider for ticket availability (sold count) for an event.
/// Uses SQL aggregation - only fetches the count, not all tickets.
final ticketAvailabilityProvider =
    FutureProvider.family<TicketAvailability, String>((ref, eventId) async {
  final repository = ref.watch(eventRepositoryProvider);
  return repository.getTicketAvailability(eventId);
});

/// Convenience provider for just the sold count.
final ticketSoldCountProvider =
    FutureProvider.family<int, String>((ref, eventId) async {
  final availability = await ref.watch(ticketAvailabilityProvider(eventId).future);
  return availability.soldCount;
});
