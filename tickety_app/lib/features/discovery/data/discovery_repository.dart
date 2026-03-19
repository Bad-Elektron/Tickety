import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/discovery_models.dart';

const _tag = 'DiscoveryRepository';

/// Repository for discovery algorithm data: weights, scores, feed, and preview.
class DiscoveryRepository {
  final _client = SupabaseService.instance.client;

  // ── Weights ────────────────────────────────────────────────

  /// Fetch all discovery weights.
  Future<List<DiscoveryWeight>> getWeights() async {
    AppLogger.debug('Fetching discovery weights', tag: _tag);
    final response = await _client
        .from('discovery_weights')
        .select()
        .order('key');
    return (response as List)
        .map((json) => DiscoveryWeight.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Update a single weight (logs to history server-side).
  Future<void> updateWeight(String key, double newWeight) async {
    AppLogger.debug('Updating weight $key → $newWeight', tag: _tag);
    final userId = SupabaseService.instance.currentUser?.id;
    await _client.rpc('update_discovery_weight', params: {
      'p_key': key,
      'p_new_weight': newWeight,
      'p_changed_by': userId,
    });
  }

  /// Batch-update multiple weights.
  Future<void> updateWeights(Map<String, double> weights) async {
    AppLogger.debug('Batch updating ${weights.length} weights', tag: _tag);
    for (final entry in weights.entries) {
      await updateWeight(entry.key, entry.value);
    }
  }

  // ── Weight History ─────────────────────────────────────────

  /// Fetch weight change history (most recent first).
  Future<List<WeightHistoryEntry>> getWeightHistory({int limit = 20}) async {
    AppLogger.debug('Fetching weight history', tag: _tag);
    final response = await _client
        .from('discovery_weight_history')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (response as List)
        .map((json) =>
            WeightHistoryEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ── Personalized Feed ──────────────────────────────────────

  /// Get the personalized event feed for a user.
  /// Returns event IDs with scores. Caller joins with event data.
  Future<List<EventScore>> getPersonalizedFeed({
    String? userId,
    double? lat,
    double? lng,
    int page = 0,
    int pageSize = 20,
  }) async {
    AppLogger.debug(
      'Fetching personalized feed (user: $userId, page: $page)',
      tag: _tag,
    );
    final response = await _client.rpc('get_personalized_feed', params: {
      'p_user_id': userId,
      'p_lat': lat,
      'p_lng': lng,
      'p_page': page,
      'p_page_size': pageSize,
    });
    return (response as List)
        .map((json) => EventScore.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ── Preview ────────────────────────────────────────────────

  /// Preview feed ranking with hypothetical weights (read-only).
  Future<List<FeedPreviewItem>> previewFeed({
    required Map<String, double> weights,
    int limit = 10,
  }) async {
    AppLogger.debug('Previewing feed with custom weights', tag: _tag);
    final response = await _client.rpc('preview_feed_with_weights', params: {
      'p_weights': weights,
      'p_limit': limit,
    });
    return (response as List)
        .map((json) =>
            FeedPreviewItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ── Tag Affinity ───────────────────────────────────────────

  /// Update tag affinity for a user based on an interaction.
  Future<void> updateTagAffinity({
    required String userId,
    required String tag,
    required String interactionType,
  }) async {
    await _client.rpc('update_user_tag_affinity', params: {
      'p_user_id': userId,
      'p_tag': tag,
      'p_interaction_type': interactionType,
    });
  }

  /// Update tag affinity for multiple tags at once (e.g., all tags on an event).
  Future<void> updateTagAffinityBatch({
    required String userId,
    required List<String> tags,
    required String interactionType,
  }) async {
    for (final tag in tags) {
      await updateTagAffinity(
        userId: userId,
        tag: tag,
        interactionType: interactionType,
      );
    }
  }

  // ── Platform Tag Affinity Stats ────────────────────────────

  /// Get platform-wide tag affinity summary for admin dashboard.
  Future<List<TagAffinityStat>> getPlatformTagAffinity({
    int limit = 15,
  }) async {
    AppLogger.debug('Fetching platform tag affinity stats', tag: _tag);
    final response = await _client.rpc('get_platform_tag_affinity', params: {
      'p_limit': limit,
    });
    return (response as List)
        .map((json) =>
            TagAffinityStat.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ── Featured Events ────────────────────────────────────────

  /// Get featured event IDs (pinned first, then top-scored).
  Future<List<FeaturedEventEntry>> getFeaturedEvents({
    int limit = 5,
  }) async {
    AppLogger.debug('Fetching featured events', tag: _tag);
    final response = await _client.rpc('get_featured_events', params: {
      'p_limit': limit,
    });
    return (response as List)
        .map((json) =>
            FeaturedEventEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Toggle featured status for an event. Returns new featured state.
  Future<bool> toggleFeaturedEvent(String eventId) async {
    AppLogger.debug('Toggling featured for event $eventId', tag: _tag);
    final result = await _client.rpc('toggle_featured_event', params: {
      'p_event_id': eventId,
    });
    return result as bool;
  }
}
