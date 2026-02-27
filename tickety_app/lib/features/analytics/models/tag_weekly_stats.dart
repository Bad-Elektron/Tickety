import 'package:flutter/foundation.dart';

/// Weekly statistics for a single tag from the analytics cache.
@immutable
class TagWeeklyStats {
  final String tagId;
  final DateTime weekStart;
  final String? city;
  final String? country;
  final int eventCount;
  final int avgPriceCents;
  final int totalTicketsSold;
  final int totalRevenueCents;

  const TagWeeklyStats({
    required this.tagId,
    required this.weekStart,
    this.city,
    this.country,
    required this.eventCount,
    required this.avgPriceCents,
    required this.totalTicketsSold,
    required this.totalRevenueCents,
  });

  /// Formatted average price.
  String get formattedAvgPrice {
    if (avgPriceCents == 0) return 'Free';
    final dollars = avgPriceCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted revenue.
  String get formattedRevenue {
    final dollars = totalRevenueCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Short label for the week (e.g. "Feb 10").
  String get weekLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[weekStart.month - 1]} ${weekStart.day}';
  }

  factory TagWeeklyStats.fromJson(Map<String, dynamic> json) {
    return TagWeeklyStats(
      tagId: json['tag_id'] as String,
      weekStart: DateTime.parse(json['week_start'] as String),
      city: json['city'] as String?,
      country: json['country'] as String?,
      eventCount: json['event_count'] as int? ?? 0,
      avgPriceCents: json['avg_price_cents'] as int? ?? 0,
      totalTicketsSold: json['total_tickets_sold'] as int? ?? 0,
      totalRevenueCents: (json['total_revenue_cents'] as num?)?.toInt() ?? 0,
    );
  }
}
