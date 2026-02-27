import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/analytics/data/analytics_repository.dart';
import '../../features/analytics/models/market_snapshot.dart';
import '../../features/analytics/models/tag_weekly_stats.dart';
import '../../features/analytics/models/trending_tag.dart';
import '../errors/errors.dart';

const _tag = 'AnalyticsProvider';

/// State for the platform analytics dashboard.
class AnalyticsState {
  final List<TrendingTag> trendingTags;
  final List<TagWeeklyStats> selectedTagStats;
  final String? selectedTagId;
  final String? selectedCity;
  final List<String> availableCities;
  final DateTime? lastRefreshed;
  final bool isLoading;
  final bool isLoadingTagDetail;
  final String? error;
  final List<MarketSnapshot> marketSnapshots;
  final MarketComparison? selectedTagMarketComparison;

  const AnalyticsState({
    this.trendingTags = const [],
    this.selectedTagStats = const [],
    this.selectedTagId,
    this.selectedCity,
    this.availableCities = const [],
    this.lastRefreshed,
    this.isLoading = false,
    this.isLoadingTagDetail = false,
    this.error,
    this.marketSnapshots = const [],
    this.selectedTagMarketComparison,
  });

  AnalyticsState copyWith({
    List<TrendingTag>? trendingTags,
    List<TagWeeklyStats>? selectedTagStats,
    String? selectedTagId,
    String? selectedCity,
    List<String>? availableCities,
    DateTime? lastRefreshed,
    bool? isLoading,
    bool? isLoadingTagDetail,
    String? error,
    bool clearError = false,
    bool clearSelectedTag = false,
    bool clearSelectedCity = false,
    List<MarketSnapshot>? marketSnapshots,
    MarketComparison? selectedTagMarketComparison,
    bool clearSelectedTagMarket = false,
  }) {
    return AnalyticsState(
      trendingTags: trendingTags ?? this.trendingTags,
      selectedTagStats: selectedTagStats ?? this.selectedTagStats,
      selectedTagId: clearSelectedTag ? null : (selectedTagId ?? this.selectedTagId),
      selectedCity: clearSelectedCity ? null : (selectedCity ?? this.selectedCity),
      availableCities: availableCities ?? this.availableCities,
      lastRefreshed: lastRefreshed ?? this.lastRefreshed,
      isLoading: isLoading ?? this.isLoading,
      isLoadingTagDetail: isLoadingTagDetail ?? this.isLoadingTagDetail,
      error: clearError ? null : (error ?? this.error),
      marketSnapshots: marketSnapshots ?? this.marketSnapshots,
      selectedTagMarketComparison: clearSelectedTagMarket
          ? null
          : (selectedTagMarketComparison ?? this.selectedTagMarketComparison),
    );
  }

  /// Total events this week across all trending tags.
  int get totalEventsThisWeek =>
      trendingTags.fold(0, (sum, t) => sum + t.currentWeekCount);

  /// The tag with the highest trend score.
  TrendingTag? get hottestTag =>
      trendingTags.isNotEmpty ? trendingTags.first : null;

  /// The tag with the highest average price.
  TrendingTag? get highestPriceTag {
    if (trendingTags.isEmpty) return null;
    return trendingTags.reduce(
      (a, b) => a.avgPriceCents > b.avgPriceCents ? a : b,
    );
  }

  /// Build MarketComparison objects grouped by tag from all snapshots.
  Map<String, MarketComparison> get marketComparisonsByTag {
    final map = <String, ({MarketSnapshot? tm, MarketSnapshot? sg})>{};
    for (final s in marketSnapshots) {
      final existing = map[s.tagId] ?? (tm: null, sg: null);
      if (s.source == MarketSource.ticketmaster) {
        map[s.tagId] = (tm: s, sg: existing.sg);
      } else {
        map[s.tagId] = (tm: existing.tm, sg: s);
      }
    }
    return map.map((tagId, pair) => MapEntry(
      tagId,
      MarketComparison(
        tagId: tagId,
        ticketmaster: pair.tm,
        seatgeek: pair.sg,
      ),
    ));
  }
}

/// Notifier for managing platform analytics state.
class AnalyticsNotifier extends StateNotifier<AnalyticsState> {
  final IAnalyticsRepository _repository;

  AnalyticsNotifier(this._repository) : super(const AnalyticsState());

  /// Load the dashboard: trending tags, available cities, last refresh time,
  /// and market snapshots (all in parallel).
  Future<void> loadDashboard() async {
    if (state.isLoading) return;

    AppLogger.debug('Loading analytics dashboard', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final results = await Future.wait([
        _repository.getTrendingTags(city: state.selectedCity),
        _repository.getAvailableCities(),
        _repository.getLastRefreshTime(),
        _repository.getMarketSnapshots(),
      ]);

      state = state.copyWith(
        trendingTags: results[0] as List<TrendingTag>,
        availableCities: results[1] as List<String>,
        lastRefreshed: results[2] as DateTime?,
        marketSnapshots: results[3] as List<MarketSnapshot>,
        isLoading: false,
      );

      AppLogger.info(
        'Dashboard loaded: ${state.trendingTags.length} trending tags, '
        '${state.availableCities.length} cities, '
        '${state.marketSnapshots.length} market snapshots',
        tag: _tag,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load analytics dashboard',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
    }
  }

  /// Load weekly detail and market comparison for a specific tag.
  Future<void> loadTagDetail(String tagId) async {
    AppLogger.debug('Loading tag detail: $tagId', tag: _tag);
    state = state.copyWith(
      isLoadingTagDetail: true,
      selectedTagId: tagId,
      clearError: true,
      clearSelectedTagMarket: true,
    );

    try {
      final results = await Future.wait([
        _repository.getTagWeeklyStats(tagId, city: state.selectedCity),
        _repository.getMarketSnapshotsForTag(tagId),
      ]);

      final stats = results[0] as List<TagWeeklyStats>;
      final snapshots = results[1] as List<MarketSnapshot>;

      // Build MarketComparison from the snapshots
      MarketSnapshot? tm;
      MarketSnapshot? sg;
      for (final s in snapshots) {
        if (s.source == MarketSource.ticketmaster) tm = s;
        if (s.source == MarketSource.seatgeek) sg = s;
      }
      final comparison = (tm != null || sg != null)
          ? MarketComparison(tagId: tagId, ticketmaster: tm, seatgeek: sg)
          : null;

      state = state.copyWith(
        selectedTagStats: stats,
        selectedTagMarketComparison: comparison,
        isLoadingTagDetail: false,
      );

      AppLogger.debug(
        'Loaded ${stats.length} weekly rows + market comparison for tag $tagId',
        tag: _tag,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load tag detail for $tagId',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoadingTagDetail: false,
        error: appError.userMessage,
      );
    }
  }

  /// Change the city filter and re-fetch data.
  Future<void> setCity(String? city) async {
    if (city == state.selectedCity) return;

    AppLogger.debug(
      'City filter changed: ${city ?? 'All Locations'}',
      tag: _tag,
    );

    state = state.copyWith(
      clearSelectedCity: city == null,
      selectedCity: city,
    );

    await loadDashboard();

    // If a tag was selected, reload its detail too
    final tagId = state.selectedTagId;
    if (tagId != null) {
      await loadTagDetail(tagId);
    }
  }

  /// Clear error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ============================================================
// PROVIDERS
// ============================================================

/// Repository provider — can be overridden for testing.
final analyticsRepositoryProvider = Provider<IAnalyticsRepository>((ref) {
  return AnalyticsRepository();
});

/// Main analytics provider for the dashboard.
final analyticsProvider =
    StateNotifierProvider<AnalyticsNotifier, AnalyticsState>((ref) {
  final repository = ref.watch(analyticsRepositoryProvider);
  return AnalyticsNotifier(repository);
});
