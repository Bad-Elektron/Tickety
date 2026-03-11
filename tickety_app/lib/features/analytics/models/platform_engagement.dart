/// Platform-wide engagement summary from `get_platform_engagement_summary` RPC.
class PlatformEngagement {
  final int totalViews30d;
  final int uniqueViewers30d;
  final double avgConversionRate;
  final List<WeeklyViews> weeklyViews;
  final List<TopEventEngagement> topEvents;

  const PlatformEngagement({
    required this.totalViews30d,
    required this.uniqueViewers30d,
    required this.avgConversionRate,
    required this.weeklyViews,
    required this.topEvents,
  });

  factory PlatformEngagement.fromJson(Map<String, dynamic> json) {
    return PlatformEngagement(
      totalViews30d: json['total_views_30d'] as int? ?? 0,
      uniqueViewers30d: json['total_unique_viewers_30d'] as int? ?? 0,
      avgConversionRate: (json['avg_conversion_rate'] as num?)?.toDouble() ?? 0,
      weeklyViews: (json['weekly_views'] as List<dynamic>?)
              ?.map((e) => WeeklyViews.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      topEvents: (json['top_events'] as List<dynamic>?)
              ?.map((e) => TopEventEngagement.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  static const empty = PlatformEngagement(
    totalViews30d: 0,
    uniqueViewers30d: 0,
    avgConversionRate: 0,
    weeklyViews: [],
    topEvents: [],
  );
}

class WeeklyViews {
  final String weekStart;
  final int views;

  const WeeklyViews({required this.weekStart, required this.views});

  factory WeeklyViews.fromJson(Map<String, dynamic> json) {
    return WeeklyViews(
      weekStart: json['week_start'] as String? ?? '',
      views: json['views'] as int? ?? 0,
    );
  }
}

class TopEventEngagement {
  final String eventId;
  final String title;
  final int totalViews;
  final int uniqueViewers;
  final double conversionRate;

  const TopEventEngagement({
    required this.eventId,
    required this.title,
    required this.totalViews,
    required this.uniqueViewers,
    required this.conversionRate,
  });

  factory TopEventEngagement.fromJson(Map<String, dynamic> json) {
    return TopEventEngagement(
      eventId: json['event_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown',
      totalViews: json['total_views'] as int? ?? 0,
      uniqueViewers: json['unique_viewers'] as int? ?? 0,
      conversionRate: (json['conversion_rate'] as num?)?.toDouble() ?? 0,
    );
  }
}
