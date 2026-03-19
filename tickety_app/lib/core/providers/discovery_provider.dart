import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/discovery/data/discovery_repository.dart';
import '../../features/discovery/models/discovery_models.dart';
import '../../features/events/data/data.dart';
import '../../features/events/models/event_model.dart';
import '../errors/errors.dart';
import 'auth_provider.dart';
import 'events_provider.dart';

const _tag = 'DiscoveryProvider';

// ============================================================
// DISCOVERY REPOSITORY PROVIDER
// ============================================================

final discoveryRepositoryProvider = Provider<DiscoveryRepository>((ref) {
  return DiscoveryRepository();
});

// ============================================================
// DISCOVERY FEED (replaces chronological feed)
// ============================================================

/// State for the discovery-scored event feed.
class DiscoveryFeedState {
  final List<EventModel> events;
  final Map<String, EventScore> scores;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int currentPage;
  final bool hasMore;
  final int pageSize;

  const DiscoveryFeedState({
    this.events = const [],
    this.scores = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.currentPage = 0,
    this.hasMore = true,
    this.pageSize = 20,
  });

  bool get canLoadMore => hasMore && !isLoading && !isLoadingMore;

  DiscoveryFeedState copyWith({
    List<EventModel>? events,
    Map<String, EventScore>? scores,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    int? currentPage,
    bool? hasMore,
    bool clearError = false,
  }) {
    return DiscoveryFeedState(
      events: events ?? this.events,
      scores: scores ?? this.scores,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      pageSize: pageSize,
    );
  }
}

class DiscoveryFeedNotifier extends StateNotifier<DiscoveryFeedState> {
  final DiscoveryRepository _discoveryRepo;
  final EventRepository _eventRepo;
  final String? _userId;

  DiscoveryFeedNotifier(
    this._discoveryRepo,
    this._eventRepo,
    this._userId,
  ) : super(const DiscoveryFeedState()) {
    loadFeed();
  }

  /// Load the first page of scored events.
  Future<void> loadFeed() async {
    AppLogger.debug('Loading discovery feed', tag: _tag);
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentPage: 0,
      hasMore: true,
    );

    try {
      final feedScores = await _discoveryRepo.getPersonalizedFeed(
        userId: _userId,
        page: 0,
        pageSize: state.pageSize,
      );

      final hasMore = feedScores.length > state.pageSize;
      final trimmedScores =
          hasMore ? feedScores.take(state.pageSize).toList() : feedScores;

      // Fetch full event data for these IDs
      final events = await _fetchEvents(trimmedScores);

      final scoreMap = {
        for (final s in trimmedScores) s.eventId: s,
      };

      AppLogger.info(
        'Loaded ${events.length} scored events (hasMore: $hasMore)',
        tag: _tag,
      );

      state = state.copyWith(
        events: events,
        scores: scoreMap,
        isLoading: false,
        currentPage: 0,
        hasMore: hasMore,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load discovery feed, falling back to chronological',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      // Fall back to chronological events
      await _fallbackToChronological();
    }
  }

  /// Load more events (next page).
  Future<void> loadMore() async {
    if (!state.canLoadMore) return;

    final nextPage = state.currentPage + 1;
    AppLogger.debug('Loading more discovery events (page: $nextPage)', tag: _tag);
    state = state.copyWith(isLoadingMore: true);

    try {
      final feedScores = await _discoveryRepo.getPersonalizedFeed(
        userId: _userId,
        page: nextPage,
        pageSize: state.pageSize,
      );

      final hasMore = feedScores.length > state.pageSize;
      final trimmedScores =
          hasMore ? feedScores.take(state.pageSize).toList() : feedScores;

      final newEvents = await _fetchEvents(trimmedScores);
      final newScoreMap = {
        ...state.scores,
        for (final s in trimmedScores) s.eventId: s,
      };

      state = state.copyWith(
        events: [...state.events, ...newEvents],
        scores: newScoreMap,
        isLoadingMore: false,
        currentPage: nextPage,
        hasMore: hasMore,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load more discovery events',
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

  Future<void> refresh() => loadFeed();

  /// Fetch full EventModel data for a list of scores.
  Future<List<EventModel>> _fetchEvents(List<EventScore> scores) async {
    if (scores.isEmpty) return [];
    final eventIds = scores.map((s) => s.eventId).toList();
    final events = <EventModel>[];
    for (final id in eventIds) {
      final event = await _eventRepo.getEventById(id);
      if (event != null) events.add(event);
    }
    // Preserve score order
    final idOrder = {for (var i = 0; i < eventIds.length; i++) eventIds[i]: i};
    events.sort((a, b) => (idOrder[a.id] ?? 0).compareTo(idOrder[b.id] ?? 0));
    return events;
  }

  /// Fallback when discovery RPC fails (e.g., table not yet migrated).
  Future<void> _fallbackToChronological() async {
    try {
      final result = await _eventRepo.getUpcomingEvents(
        page: 0,
        pageSize: state.pageSize,
      );
      state = state.copyWith(
        events: result.items,
        scores: {},
        isLoading: false,
        currentPage: 0,
        hasMore: result.hasMore,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      state = state.copyWith(
        events: PlaceholderEvents.upcoming,
        isLoading: false,
        error: appError.userMessage,
        hasMore: false,
      );
    }
  }
}

/// Main discovery feed provider. Replaces chronological `eventsProvider` for the home screen.
final discoveryFeedProvider =
    StateNotifierProvider<DiscoveryFeedNotifier, DiscoveryFeedState>((ref) {
  final discoveryRepo = ref.watch(discoveryRepositoryProvider);
  final eventRepo = ref.watch(eventRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return DiscoveryFeedNotifier(discoveryRepo, eventRepo, userId);
});

/// Convenience providers for discovery feed.
final discoveryLoadingProvider = Provider<bool>((ref) {
  return ref.watch(discoveryFeedProvider).isLoading;
});

final discoveryLoadingMoreProvider = Provider<bool>((ref) {
  return ref.watch(discoveryFeedProvider).isLoadingMore;
});

final discoveryCanLoadMoreProvider = Provider<bool>((ref) {
  return ref.watch(discoveryFeedProvider).canLoadMore;
});

// ============================================================
// DISCOVERY WEIGHTS (Admin Tuning)
// ============================================================

/// State for the admin algorithm tuning dashboard.
class DiscoveryWeightsState {
  final List<DiscoveryWeight> weights;
  final List<WeightHistoryEntry> history;
  final List<FeedPreviewItem> preview;
  final bool isLoading;
  final bool isPreviewing;
  final bool isSaving;
  final String? error;

  const DiscoveryWeightsState({
    this.weights = const [],
    this.history = const [],
    this.preview = const [],
    this.isLoading = false,
    this.isPreviewing = false,
    this.isSaving = false,
    this.error,
  });

  DiscoveryWeightsState copyWith({
    List<DiscoveryWeight>? weights,
    List<WeightHistoryEntry>? history,
    List<FeedPreviewItem>? preview,
    bool? isLoading,
    bool? isPreviewing,
    bool? isSaving,
    String? error,
    bool clearError = false,
    bool clearPreview = false,
  }) {
    return DiscoveryWeightsState(
      weights: weights ?? this.weights,
      history: history ?? this.history,
      preview: clearPreview ? [] : (preview ?? this.preview),
      isLoading: isLoading ?? this.isLoading,
      isPreviewing: isPreviewing ?? this.isPreviewing,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DiscoveryWeightsNotifier extends StateNotifier<DiscoveryWeightsState> {
  final DiscoveryRepository _repo;

  DiscoveryWeightsNotifier(this._repo) : super(const DiscoveryWeightsState());

  /// Load weights and history from DB.
  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final weights = await _repo.getWeights();
      final history = await _repo.getWeightHistory();
      state = state.copyWith(
        weights: weights,
        history: history,
        isLoading: false,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error('Failed to load weights', error: e, stackTrace: s, tag: _tag);
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
    }
  }

  /// Update a local weight slider value (does NOT persist yet).
  void setLocalWeight(String key, double value) {
    final updated = state.weights.map((w) {
      if (w.key == key) return w.copyWith(weight: value);
      return w;
    }).toList();
    state = state.copyWith(weights: updated, clearPreview: true);
  }

  /// Preview feed with current local weights.
  Future<void> previewFeed() async {
    state = state.copyWith(isPreviewing: true, clearError: true);
    try {
      final weightMap = {
        for (final w in state.weights)
          if (!w.isPersonalization) w.key: w.weight,
      };
      final preview = await _repo.previewFeed(weights: weightMap);
      state = state.copyWith(preview: preview, isPreviewing: false);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error('Preview failed', error: e, stackTrace: s, tag: _tag);
      state = state.copyWith(
        isPreviewing: false,
        error: appError.userMessage,
      );
    }
  }

  /// Persist current local weights to DB.
  Future<void> applyWeights() async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final weightMap = {
        for (final w in state.weights) w.key: w.weight,
      };
      await _repo.updateWeights(weightMap);
      // Reload to get fresh timestamps + history
      await load();
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error('Failed to save weights', error: e, stackTrace: s, tag: _tag);
      state = state.copyWith(
        isSaving: false,
        error: appError.userMessage,
      );
    }
  }
}

/// Provider for the admin algorithm tuning dashboard.
final discoveryWeightsProvider =
    StateNotifierProvider<DiscoveryWeightsNotifier, DiscoveryWeightsState>(
        (ref) {
  final repo = ref.watch(discoveryRepositoryProvider);
  return DiscoveryWeightsNotifier(repo);
});

// ============================================================
// TAG AFFINITY TRACKING
// ============================================================

/// Provider to track tag affinity on event interactions.
/// Call this when a user views/shares/purchases an event.
final trackTagAffinityProvider =
    Provider<TagAffinityTracker>((ref) {
  final repo = ref.watch(discoveryRepositoryProvider);
  return TagAffinityTracker(repo);
});

class TagAffinityTracker {
  final DiscoveryRepository _repo;

  TagAffinityTracker(this._repo);

  /// Track a user interaction with an event's tags.
  Future<void> track({
    required String userId,
    required List<String> tags,
    required String interactionType,
  }) async {
    if (tags.isEmpty) return;
    try {
      await _repo.updateTagAffinityBatch(
        userId: userId,
        tags: tags,
        interactionType: interactionType,
      );
    } catch (e) {
      // Non-critical — don't block the user
      AppLogger.debug('Tag affinity update failed: $e', tag: _tag);
    }
  }
}

// ============================================================
// PLATFORM TAG AFFINITY (Admin Dashboard)
// ============================================================

/// Provider for platform-wide tag affinity stats (admin chart).
final platformTagAffinityProvider =
    FutureProvider<List<TagAffinityStat>>((ref) async {
  final repo = ref.watch(discoveryRepositoryProvider);
  return repo.getPlatformTagAffinity();
});

// ============================================================
// FEATURED EVENTS (Score-based + hand-pinned)
// ============================================================

/// Provider for featured events using discovery scores.
/// Hand-pinned events appear first, then top-scored events fill remaining slots.
final discoveryFeaturedProvider =
    FutureProvider<List<EventModel>>((ref) async {
  final discoveryRepo = ref.watch(discoveryRepositoryProvider);
  final eventRepo = ref.watch(eventRepositoryProvider);

  try {
    final entries = await discoveryRepo.getFeaturedEvents(limit: 5);
    final events = <EventModel>[];
    for (final entry in entries) {
      final event = await eventRepo.getEventById(entry.eventId);
      if (event != null) events.add(event);
    }
    return events;
  } catch (e) {
    // Fallback to chronological if RPC unavailable
    AppLogger.debug('Featured RPC failed, falling back: $e', tag: _tag);
    return eventRepo.getFeaturedEvents(limit: 5);
  }
});

/// Provider to toggle featured status for an event.
final toggleFeaturedProvider =
    Provider<Future<bool> Function(String)>((ref) {
  final repo = ref.watch(discoveryRepositoryProvider);
  return (String eventId) async {
    final result = await repo.toggleFeaturedEvent(eventId);
    // Invalidate featured cache so it refreshes
    ref.invalidate(discoveryFeaturedProvider);
    return result;
  };
});
