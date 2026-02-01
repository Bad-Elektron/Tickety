/// Pre-aggregated analytics data for an event.
///
/// This data comes from the `get_event_analytics` database function,
/// which computes stats server-side instead of fetching all ticket rows.
class EventAnalytics {
  final int totalSold;
  final int checkedIn;
  final int revenueCents;
  final List<HourlyCheckin> hourlyCheckins;
  final List<UsherStat> usherStats;

  const EventAnalytics({
    required this.totalSold,
    required this.checkedIn,
    required this.revenueCents,
    required this.hourlyCheckins,
    required this.usherStats,
  });

  factory EventAnalytics.fromJson(Map<String, dynamic> json) {
    return EventAnalytics(
      totalSold: json['total_sold'] as int? ?? 0,
      checkedIn: json['checked_in'] as int? ?? 0,
      revenueCents: json['revenue_cents'] as int? ?? 0,
      hourlyCheckins: (json['hourly_checkins'] as List<dynamic>?)
              ?.map((e) => HourlyCheckin.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      usherStats: (json['usher_stats'] as List<dynamic>?)
              ?.map((e) => UsherStat.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Check-in rate as a percentage.
  double get checkInRate {
    if (totalSold == 0) return 0;
    return (checkedIn / totalSold) * 100;
  }

  /// Remaining tickets not yet checked in.
  int get remaining => totalSold - checkedIn;

  /// Revenue formatted as dollars.
  String get formattedRevenue {
    final dollars = revenueCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Peak check-in hour (or null if no check-ins).
  int? get peakHour {
    if (hourlyCheckins.isEmpty) return null;
    return hourlyCheckins.reduce((a, b) => a.count > b.count ? a : b).hour;
  }

  /// Empty analytics for when no data exists.
  static const empty = EventAnalytics(
    totalSold: 0,
    checkedIn: 0,
    revenueCents: 0,
    hourlyCheckins: [],
    usherStats: [],
  );
}

/// Check-in count for a specific hour.
class HourlyCheckin {
  final int hour;
  final int count;

  const HourlyCheckin({
    required this.hour,
    required this.count,
  });

  factory HourlyCheckin.fromJson(Map<String, dynamic> json) {
    return HourlyCheckin(
      hour: json['hour'] as int,
      count: json['count'] as int,
    );
  }

  /// Hour formatted for display (e.g., "2 PM").
  String get formattedHour {
    if (hour == 0) return '12 AM';
    if (hour == 12) return '12 PM';
    if (hour < 12) return '$hour AM';
    return '${hour - 12} PM';
  }
}

/// Check-in count by usher/staff member.
class UsherStat {
  final String userId;
  final int count;

  const UsherStat({
    required this.userId,
    required this.count,
  });

  factory UsherStat.fromJson(Map<String, dynamic> json) {
    return UsherStat(
      userId: json['user_id'] as String,
      count: json['count'] as int,
    );
  }

  /// Short display name (first 6 chars of user ID).
  String get displayName {
    final shortId = userId.length > 6 ? userId.substring(0, 6) : userId;
    return 'Staff $shortId...';
  }
}
