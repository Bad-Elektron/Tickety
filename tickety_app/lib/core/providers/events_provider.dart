import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/events/data/data.dart';
import '../../features/events/models/event_model.dart';
import '../errors/errors.dart';
import 'auth_provider.dart';

const _tag = 'EventsProvider';

/// State for the events list.
class EventsState {
  final List<EventModel> events;
  final List<EventModel> featuredEvents;
  final bool isLoading;
  final String? error;
  final bool isUsingPlaceholders;

  const EventsState({
    this.events = const [],
    this.featuredEvents = const [],
    this.isLoading = false,
    this.error,
    this.isUsingPlaceholders = false,
  });

  EventsState copyWith({
    List<EventModel>? events,
    List<EventModel>? featuredEvents,
    bool? isLoading,
    String? error,
    bool? isUsingPlaceholders,
    bool clearError = false,
  }) {
    return EventsState(
      events: events ?? this.events,
      featuredEvents: featuredEvents ?? this.featuredEvents,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isUsingPlaceholders: isUsingPlaceholders ?? this.isUsingPlaceholders,
    );
  }
}

/// Notifier that manages events data.
class EventsNotifier extends StateNotifier<EventsState> {
  final EventRepository _repository;

  EventsNotifier(this._repository) : super(const EventsState()) {
    loadEvents();
  }

  /// Load all upcoming events.
  Future<void> loadEvents() async {
    AppLogger.debug('Loading upcoming events', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final events = await _repository.getUpcomingEvents();
      final featured = await _repository.getFeaturedEvents(limit: 5);

      AppLogger.info(
        'Loaded ${events.length} events (${featured.length} featured)',
        tag: _tag,
      );

      state = state.copyWith(
        events: events,
        featuredEvents: featured,
        isLoading: false,
        isUsingPlaceholders: false,
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

// ============================================================
// MY EVENTS (User's created events)
// ============================================================

/// State for user's created events.
class MyEventsState {
  final List<EventModel> events;
  final bool isLoading;
  final String? error;

  const MyEventsState({
    this.events = const [],
    this.isLoading = false,
    this.error,
  });

  MyEventsState copyWith({
    List<EventModel>? events,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return MyEventsState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
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

  /// Load events created by the current user.
  Future<void> loadMyEvents() async {
    if (!_isAuthenticated) {
      AppLogger.debug('Not authenticated, skipping my events load', tag: _tag);
      state = state.copyWith(events: [], isLoading: false);
      return;
    }

    AppLogger.debug('Loading user\'s events', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final events = await _repository.getMyEvents();
      AppLogger.info('Loaded ${events.length} user events', tag: _tag);
      state = state.copyWith(events: events, isLoading: false);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load user events',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
    }
  }

  /// Refresh events.
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
