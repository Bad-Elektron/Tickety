import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/market_snapshot.dart';
import '../models/platform_engagement.dart';
import '../models/tag_weekly_stats.dart';
import '../models/trending_tag.dart';
import 'i_analytics_repository.dart';

export 'i_analytics_repository.dart' show IAnalyticsRepository;

const _tag = 'AnalyticsRepository';

/// Supabase implementation of [IAnalyticsRepository].
///
/// All reads are simple SELECTs from pre-computed cache tables.
class AnalyticsRepository implements IAnalyticsRepository {
  final _client = SupabaseService.instance.client;

  @override
  Future<PlatformEngagement> getPlatformEngagement({String? city}) async {
    AppLogger.debug(
      'Fetching platform engagement${city != null ? ' for city: $city' : ''}',
      tag: _tag,
    );

    try {
      final response = await _client.rpc(
        'get_platform_engagement_summary',
        params: {'p_city': city},
      );

      if (response == null) return PlatformEngagement.empty;
      return PlatformEngagement.fromJson(response as Map<String, dynamic>);
    } catch (e, s) {
      AppLogger.error('Failed to fetch platform engagement', error: e, stackTrace: s, tag: _tag);
      rethrow;
    }
  }

  @override
  Future<List<TrendingTag>> getTrendingTags({String? city}) async {
    AppLogger.debug(
      'Fetching trending tags${city != null ? ' for city: $city' : ' (global)'}',
      tag: _tag,
    );

    try {
      var query = _client
          .from('analytics_trending_tags')
          .select();

      if (city != null) {
        query = query.eq('city', city);
      } else {
        query = query.isFilter('city', null);
      }

      final response = await query
          .order('trend_score', ascending: false)
          .limit(20);

      final tags = (response as List<dynamic>)
          .map((json) => TrendingTag.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.debug('Fetched ${tags.length} trending tags', tag: _tag);
      return tags;
    } catch (e, s) {
      AppLogger.error('Failed to fetch trending tags', error: e, stackTrace: s, tag: _tag);
      rethrow;
    }
  }

  @override
  Future<List<TagWeeklyStats>> getTagWeeklyStats(
    String tagId, {
    String? city,
    int weeks = 12,
  }) async {
    AppLogger.debug('Fetching weekly stats for tag: $tagId (weeks: $weeks)', tag: _tag);

    try {
      final cutoff = DateTime.now().subtract(Duration(days: weeks * 7));
      final cutoffStr = cutoff.toIso8601String().substring(0, 10);

      var query = _client
          .from('analytics_tag_weekly')
          .select()
          .eq('tag_id', tagId)
          .gte('week_start', cutoffStr);

      if (city != null) {
        query = query.eq('city', city);
      } else {
        query = query.isFilter('city', null);
      }

      final response = await query.order('week_start', ascending: true);

      final stats = (response as List<dynamic>)
          .map((json) => TagWeeklyStats.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.debug('Fetched ${stats.length} weekly stat rows for tag $tagId', tag: _tag);
      return stats;
    } catch (e, s) {
      AppLogger.error(
        'Failed to fetch weekly stats for tag $tagId',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      rethrow;
    }
  }

  @override
  Future<List<String>> getAvailableCities() async {
    AppLogger.debug('Fetching available cities', tag: _tag);

    try {
      final response = await _client
          .from('analytics_tag_weekly')
          .select('city')
          .not('city', 'is', null)
          .order('city', ascending: true);

      final cities = (response as List<dynamic>)
          .map((json) => (json as Map<String, dynamic>)['city'] as String)
          .toSet()
          .toList()
        ..sort();

      AppLogger.debug('Found ${cities.length} distinct cities', tag: _tag);
      return cities;
    } catch (e, s) {
      AppLogger.error('Failed to fetch available cities', error: e, stackTrace: s, tag: _tag);
      rethrow;
    }
  }

  @override
  Future<DateTime?> getLastRefreshTime() async {
    try {
      final response = await _client
          .from('analytics_cache_meta')
          .select('refreshed_at')
          .eq('key', 'last_refresh')
          .maybeSingle();

      if (response == null) return null;
      return DateTime.parse(response['refreshed_at'] as String);
    } catch (e, s) {
      AppLogger.error('Failed to fetch last refresh time', error: e, stackTrace: s, tag: _tag);
      return null;
    }
  }

  @override
  Future<List<MarketSnapshot>> getMarketSnapshots() async {
    AppLogger.debug('Fetching all market snapshots', tag: _tag);

    try {
      final response = await _client
          .from('analytics_market_snapshot')
          .select()
          .isFilter('error_message', null);

      final snapshots = (response as List<dynamic>)
          .map((json) => MarketSnapshot.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.debug('Fetched ${snapshots.length} market snapshots', tag: _tag);
      return snapshots;
    } catch (e, s) {
      AppLogger.error('Failed to fetch market snapshots', error: e, stackTrace: s, tag: _tag);
      rethrow;
    }
  }

  @override
  Future<List<MarketSnapshot>> getMarketSnapshotsForTag(String tagId) async {
    AppLogger.debug('Fetching market snapshots for tag: $tagId', tag: _tag);

    try {
      final response = await _client
          .from('analytics_market_snapshot')
          .select()
          .eq('tag_id', tagId);

      final snapshots = (response as List<dynamic>)
          .map((json) => MarketSnapshot.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.debug('Fetched ${snapshots.length} market snapshots for tag $tagId', tag: _tag);
      return snapshots;
    } catch (e, s) {
      AppLogger.error(
        'Failed to fetch market snapshots for tag $tagId',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      rethrow;
    }
  }
}
