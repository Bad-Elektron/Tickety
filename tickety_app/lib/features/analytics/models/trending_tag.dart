import 'package:flutter/foundation.dart';

import '../../events/models/event_tag.dart';

/// A trending tag with week-over-week metrics from the analytics cache.
@immutable
class TrendingTag {
  final String tagId;
  final String? city;
  final String? country;
  final int currentWeekCount;
  final int prevWeekCount;
  final double trendScore;
  final int avgPriceCents;
  final int totalEvents30d;

  const TrendingTag({
    required this.tagId,
    this.city,
    this.country,
    required this.currentWeekCount,
    required this.prevWeekCount,
    required this.trendScore,
    required this.avgPriceCents,
    required this.totalEvents30d,
  });

  /// Human-readable label derived from PredefinedTags.
  /// Strips the `custom_` prefix from user-defined tags and title-cases them.
  String get label {
    final match = PredefinedTags.all.where((t) => t.id == tagId);
    if (match.isNotEmpty) return match.first.label;
    // Custom tags are stored as "custom_some_name" — strip prefix and title-case
    final raw = tagId.startsWith('custom_') ? tagId.substring(7) : tagId;
    return raw
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Whether this tag is trending up week-over-week.
  bool get isTrendingUp => trendScore > 0;

  /// Whether this tag is trending down week-over-week.
  bool get isTrendingDown => trendScore < 0;

  /// Formatted average price.
  String get formattedAvgPrice {
    if (avgPriceCents == 0) return 'Free';
    final dollars = avgPriceCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted trend score (e.g. "+25.0%" or "-10.0%").
  String get formattedTrendScore {
    final prefix = trendScore > 0 ? '+' : '';
    return '$prefix${trendScore.toStringAsFixed(1)}%';
  }

  factory TrendingTag.fromJson(Map<String, dynamic> json) {
    return TrendingTag(
      tagId: json['tag_id'] as String,
      city: json['city'] as String?,
      country: json['country'] as String?,
      currentWeekCount: json['current_week_count'] as int? ?? 0,
      prevWeekCount: json['prev_week_count'] as int? ?? 0,
      trendScore: (json['trend_score'] as num?)?.toDouble() ?? 0,
      avgPriceCents: json['avg_price_cents'] as int? ?? 0,
      totalEvents30d: json['total_events_30d'] as int? ?? 0,
    );
  }
}
