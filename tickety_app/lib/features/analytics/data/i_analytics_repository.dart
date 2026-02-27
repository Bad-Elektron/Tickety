import '../models/market_snapshot.dart';
import '../models/tag_weekly_stats.dart';
import '../models/trending_tag.dart';

/// Abstract repository interface for platform analytics.
abstract class IAnalyticsRepository {
  /// Get trending tags, optionally filtered by city.
  Future<List<TrendingTag>> getTrendingTags({String? city});

  /// Get weekly stats for a specific tag over the last [weeks] weeks.
  Future<List<TagWeeklyStats>> getTagWeeklyStats(
    String tagId, {
    String? city,
    int weeks = 12,
  });

  /// Get all distinct cities available in the analytics data.
  Future<List<String>> getAvailableCities();

  /// Get the timestamp of the last analytics cache refresh.
  Future<DateTime?> getLastRefreshTime();

  /// Get all valid market snapshots (no error).
  Future<List<MarketSnapshot>> getMarketSnapshots();

  /// Get market snapshots for a specific tag.
  Future<List<MarketSnapshot>> getMarketSnapshotsForTag(String tagId);
}
