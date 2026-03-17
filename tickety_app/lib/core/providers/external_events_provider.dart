import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/external_events/data/external_event_repository.dart';
import '../../features/external_events/models/models.dart';

final externalEventRepositoryProvider = Provider<ExternalEventRepository>((ref) {
  return ExternalEventRepository();
});

/// State for external events in the discovery feed.
class ExternalEventsState {
  final List<ExternalEvent> events;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int currentPage;

  const ExternalEventsState({
    this.events = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.currentPage = 0,
  });

  ExternalEventsState copyWith({
    List<ExternalEvent>? events,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? currentPage,
  }) {
    return ExternalEventsState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}

class ExternalEventsNotifier extends StateNotifier<ExternalEventsState> {
  final ExternalEventRepository _repo;

  ExternalEventsNotifier(this._repo) : super(const ExternalEventsState()) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await _repo.getUpcomingExternalEvents(page: 0, pageSize: 20);
      state = state.copyWith(
        events: result.items,
        isLoading: false,
        hasMore: result.hasMore,
        currentPage: 0,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await _repo.getUpcomingExternalEvents(page: 0, pageSize: 20);
      state = state.copyWith(
        events: result.items,
        isLoading: false,
        hasMore: result.hasMore,
        currentPage: 0,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final nextPage = state.currentPage + 1;
      final result = await _repo.getUpcomingExternalEvents(page: nextPage, pageSize: 20);
      state = state.copyWith(
        events: [...state.events, ...result.items],
        isLoadingMore: false,
        hasMore: result.hasMore,
        currentPage: nextPage,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final externalEventsProvider =
    StateNotifierProvider<ExternalEventsNotifier, ExternalEventsState>((ref) {
  final repo = ref.read(externalEventRepositoryProvider);
  return ExternalEventsNotifier(repo);
});
