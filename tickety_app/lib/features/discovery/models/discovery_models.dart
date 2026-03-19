import 'package:flutter/foundation.dart';

/// A single tunable weight in the discovery algorithm.
@immutable
class DiscoveryWeight {
  final String key;
  final double weight;
  final String? description;
  final DateTime? updatedAt;

  const DiscoveryWeight({
    required this.key,
    required this.weight,
    this.description,
    this.updatedAt,
  });

  factory DiscoveryWeight.fromJson(Map<String, dynamic> json) {
    return DiscoveryWeight(
      key: json['key'] as String,
      weight: (json['weight'] as num).toDouble(),
      description: json['description'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Human-readable label for this weight key.
  String get label => switch (key) {
        'popularity' => 'Popularity',
        'velocity' => 'Velocity',
        'engagement' => 'Engagement',
        'recency' => 'Recency',
        'urgency' => 'Urgency',
        'organizer_quality' => 'Organizer Quality',
        'proximity' => 'Proximity',
        'tag_affinity' => 'Tag Affinity',
        'price_match' => 'Price Match',
        _ => key,
      };

  /// Whether this weight belongs to the personalization layer.
  bool get isPersonalization =>
      key == 'proximity' || key == 'tag_affinity' || key == 'price_match';

  DiscoveryWeight copyWith({double? weight}) {
    return DiscoveryWeight(
      key: key,
      weight: weight ?? this.weight,
      description: description,
      updatedAt: updatedAt,
    );
  }
}

/// An entry in the weight change audit trail.
@immutable
class WeightHistoryEntry {
  final String key;
  final double oldWeight;
  final double newWeight;
  final DateTime createdAt;

  const WeightHistoryEntry({
    required this.key,
    required this.oldWeight,
    required this.newWeight,
    required this.createdAt,
  });

  factory WeightHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WeightHistoryEntry(
      key: json['key'] as String,
      oldWeight: (json['old_weight'] as num).toDouble(),
      newWeight: (json['new_weight'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Human-readable label for the weight key.
  String get label => DiscoveryWeight(key: key, weight: 0).label;
}

/// Pre-computed score for a single event.
@immutable
class EventScore {
  final String eventId;
  final double compositeScore;
  final double popularityScore;
  final double velocityScore;
  final double engagementScore;
  final double recencyScore;
  final double urgencyScore;
  final double organizerQualityScore;
  final double proximityBoost;
  final double affinityBoost;
  final double priceBoost;
  final double timeDecay;
  final double finalScore;
  final int? trendingRank;

  const EventScore({
    required this.eventId,
    required this.compositeScore,
    this.popularityScore = 0,
    this.velocityScore = 0,
    this.engagementScore = 0,
    this.recencyScore = 0,
    this.urgencyScore = 0,
    this.organizerQualityScore = 0,
    this.proximityBoost = 0,
    this.affinityBoost = 0,
    this.priceBoost = 0,
    this.timeDecay = 1,
    this.finalScore = 0,
    this.trendingRank,
  });

  factory EventScore.fromJson(Map<String, dynamic> json) {
    return EventScore(
      eventId: json['event_id'] as String,
      compositeScore: (json['composite_score'] as num?)?.toDouble() ?? 0,
      popularityScore: (json['popularity_score'] as num?)?.toDouble() ?? 0,
      velocityScore: (json['velocity_score'] as num?)?.toDouble() ?? 0,
      engagementScore: (json['engagement_score'] as num?)?.toDouble() ?? 0,
      recencyScore: (json['recency_score'] as num?)?.toDouble() ?? 0,
      urgencyScore: (json['urgency_score'] as num?)?.toDouble() ?? 0,
      organizerQualityScore:
          (json['organizer_quality_score'] as num?)?.toDouble() ?? 0,
      proximityBoost: (json['proximity_boost'] as num?)?.toDouble() ?? 0,
      affinityBoost: (json['affinity_boost'] as num?)?.toDouble() ?? 0,
      priceBoost: (json['price_boost'] as num?)?.toDouble() ?? 0,
      timeDecay: (json['time_decay'] as num?)?.toDouble() ?? 1,
      finalScore: (json['final_score'] as num?)?.toDouble() ?? 0,
      trendingRank: json['trending_rank'] as int?,
    );
  }
}

/// Preview result from the admin "what-if" preview function.
@immutable
class FeedPreviewItem {
  final String eventId;
  final String eventTitle;
  final double popularityScore;
  final double velocityScore;
  final double engagementScore;
  final double recencyScore;
  final double urgencyScore;
  final double organizerQualityScore;
  final double previewComposite;
  final double currentComposite;
  final int? currentRank;
  final int previewRank;

  const FeedPreviewItem({
    required this.eventId,
    required this.eventTitle,
    this.popularityScore = 0,
    this.velocityScore = 0,
    this.engagementScore = 0,
    this.recencyScore = 0,
    this.urgencyScore = 0,
    this.organizerQualityScore = 0,
    this.previewComposite = 0,
    this.currentComposite = 0,
    this.currentRank,
    required this.previewRank,
  });

  factory FeedPreviewItem.fromJson(Map<String, dynamic> json) {
    return FeedPreviewItem(
      eventId: json['event_id'] as String,
      eventTitle: json['event_title'] as String,
      popularityScore: (json['popularity_score'] as num?)?.toDouble() ?? 0,
      velocityScore: (json['velocity_score'] as num?)?.toDouble() ?? 0,
      engagementScore: (json['engagement_score'] as num?)?.toDouble() ?? 0,
      recencyScore: (json['recency_score'] as num?)?.toDouble() ?? 0,
      urgencyScore: (json['urgency_score'] as num?)?.toDouble() ?? 0,
      organizerQualityScore:
          (json['organizer_quality_score'] as num?)?.toDouble() ?? 0,
      previewComposite:
          (json['preview_composite'] as num?)?.toDouble() ?? 0,
      currentComposite:
          (json['current_composite'] as num?)?.toDouble() ?? 0,
      currentRank: json['current_rank'] as int?,
      previewRank: json['preview_rank'] as int,
    );
  }

  /// Rank change from current to preview (positive = moved up).
  int? get rankChange {
    if (currentRank == null) return null;
    return currentRank! - previewRank;
  }
}

/// Platform-wide tag affinity stat for admin dashboard.
@immutable
class TagAffinityStat {
  final String tag;
  final int userCount;
  final double totalAffinity;
  final double avgAffinity;

  const TagAffinityStat({
    required this.tag,
    required this.userCount,
    required this.totalAffinity,
    required this.avgAffinity,
  });

  factory TagAffinityStat.fromJson(Map<String, dynamic> json) {
    return TagAffinityStat(
      tag: json['tag'] as String,
      userCount: (json['user_count'] as num).toInt(),
      totalAffinity: (json['total_affinity'] as num).toDouble(),
      avgAffinity: (json['avg_affinity'] as num).toDouble(),
    );
  }

  /// Display label (capitalize first letter).
  String get label => tag.isEmpty ? tag : '${tag[0].toUpperCase()}${tag.substring(1)}';
}

/// Entry from get_featured_events RPC.
@immutable
class FeaturedEventEntry {
  final String eventId;
  final bool isPinned;
  final double compositeScore;

  const FeaturedEventEntry({
    required this.eventId,
    required this.isPinned,
    required this.compositeScore,
  });

  factory FeaturedEventEntry.fromJson(Map<String, dynamic> json) {
    return FeaturedEventEntry(
      eventId: json['event_id'] as String,
      isPinned: json['is_pinned'] as bool? ?? false,
      compositeScore: (json['composite_score'] as num?)?.toDouble() ?? 0,
    );
  }
}
