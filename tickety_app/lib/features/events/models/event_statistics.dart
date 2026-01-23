import 'package:flutter/material.dart';

/// Statistics data for an event dashboard.
///
/// This model is designed to be easily populated from a database.
/// All fields use simple types that map directly to common database schemas.
@immutable
class EventStatistics {
  final String eventId;
  final int totalTicketsSold;
  final int totalTicketsChecked;
  final int totalRevenueCents;
  final String currency;
  final List<UsherStats> usherStats;
  final List<HourlyCheckIn> hourlyCheckIns;
  final List<TicketTypeBreakdown> ticketTypeBreakdown;
  final DateTime? peakCheckInTime;
  final double averageCheckInDurationSeconds;

  const EventStatistics({
    required this.eventId,
    required this.totalTicketsSold,
    required this.totalTicketsChecked,
    required this.totalRevenueCents,
    this.currency = 'USD',
    required this.usherStats,
    required this.hourlyCheckIns,
    required this.ticketTypeBreakdown,
    this.peakCheckInTime,
    this.averageCheckInDurationSeconds = 0,
  });

  /// Check-in rate as a percentage (0-100).
  double get checkInRate =>
      totalTicketsSold > 0 ? (totalTicketsChecked / totalTicketsSold) * 100 : 0;

  /// Formatted revenue string.
  String get formattedRevenue {
    final dollars = totalRevenueCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Creates statistics from a JSON map (for database/API integration).
  factory EventStatistics.fromJson(Map<String, dynamic> json) {
    return EventStatistics(
      eventId: json['eventId'] as String,
      totalTicketsSold: json['totalTicketsSold'] as int,
      totalTicketsChecked: json['totalTicketsChecked'] as int,
      totalRevenueCents: json['totalRevenueCents'] as int,
      currency: json['currency'] as String? ?? 'USD',
      usherStats: (json['usherStats'] as List<dynamic>)
          .map((e) => UsherStats.fromJson(e as Map<String, dynamic>))
          .toList(),
      hourlyCheckIns: (json['hourlyCheckIns'] as List<dynamic>)
          .map((e) => HourlyCheckIn.fromJson(e as Map<String, dynamic>))
          .toList(),
      ticketTypeBreakdown: (json['ticketTypeBreakdown'] as List<dynamic>)
          .map((e) => TicketTypeBreakdown.fromJson(e as Map<String, dynamic>))
          .toList(),
      peakCheckInTime: json['peakCheckInTime'] != null
          ? DateTime.parse(json['peakCheckInTime'] as String)
          : null,
      averageCheckInDurationSeconds:
          (json['averageCheckInDurationSeconds'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'totalTicketsSold': totalTicketsSold,
        'totalTicketsChecked': totalTicketsChecked,
        'totalRevenueCents': totalRevenueCents,
        'currency': currency,
        'usherStats': usherStats.map((e) => e.toJson()).toList(),
        'hourlyCheckIns': hourlyCheckIns.map((e) => e.toJson()).toList(),
        'ticketTypeBreakdown': ticketTypeBreakdown.map((e) => e.toJson()).toList(),
        'peakCheckInTime': peakCheckInTime?.toIso8601String(),
        'averageCheckInDurationSeconds': averageCheckInDurationSeconds,
      };
}

/// Statistics for an individual usher.
@immutable
class UsherStats {
  final String odentifier;
  final String name;
  final String? avatarUrl;
  final int ticketsChecked;
  final DateTime? lastCheckIn;

  const UsherStats({
    required this.odentifier,
    required this.name,
    this.avatarUrl,
    required this.ticketsChecked,
    this.lastCheckIn,
  });

  factory UsherStats.fromJson(Map<String, dynamic> json) {
    return UsherStats(
      odentifier: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      ticketsChecked: json['ticketsChecked'] as int,
      lastCheckIn: json['lastCheckIn'] != null
          ? DateTime.parse(json['lastCheckIn'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': odentifier,
        'name': name,
        'avatarUrl': avatarUrl,
        'ticketsChecked': ticketsChecked,
        'lastCheckIn': lastCheckIn?.toIso8601String(),
      };
}

/// Hourly check-in data for charting.
@immutable
class HourlyCheckIn {
  final int hour; // 0-23
  final int count;

  const HourlyCheckIn({
    required this.hour,
    required this.count,
  });

  /// Formatted hour string (e.g., "2 PM").
  String get formattedHour {
    if (hour == 0) return '12 AM';
    if (hour == 12) return '12 PM';
    if (hour < 12) return '$hour AM';
    return '${hour - 12} PM';
  }

  factory HourlyCheckIn.fromJson(Map<String, dynamic> json) {
    return HourlyCheckIn(
      hour: json['hour'] as int,
      count: json['count'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'hour': hour,
        'count': count,
      };
}

/// Breakdown by ticket type.
@immutable
class TicketTypeBreakdown {
  final String type;
  final int sold;
  final int checked;
  final int revenueCents;

  const TicketTypeBreakdown({
    required this.type,
    required this.sold,
    required this.checked,
    required this.revenueCents,
  });

  double get checkInRate => sold > 0 ? (checked / sold) * 100 : 0;

  factory TicketTypeBreakdown.fromJson(Map<String, dynamic> json) {
    return TicketTypeBreakdown(
      type: json['type'] as String,
      sold: json['sold'] as int,
      checked: json['checked'] as int,
      revenueCents: json['revenueCents'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'sold': sold,
        'checked': checked,
        'revenueCents': revenueCents,
      };
}

/// Provides placeholder statistics for development and testing.
abstract class PlaceholderStatistics {
  static EventStatistics forEvent(String eventId) {
    return EventStatistics(
      eventId: eventId,
      totalTicketsSold: 53,
      totalTicketsChecked: 38,
      totalRevenueCents: 53000,
      usherStats: const [
        UsherStats(
          odentifier: 'usher_001',
          name: 'Alex Johnson',
          ticketsChecked: 24,
          lastCheckIn: null,
        ),
        UsherStats(
          odentifier: 'usher_002',
          name: 'Sam Wilson',
          ticketsChecked: 14,
          lastCheckIn: null,
        ),
      ],
      hourlyCheckIns: const [
        HourlyCheckIn(hour: 17, count: 2),
        HourlyCheckIn(hour: 18, count: 8),
        HourlyCheckIn(hour: 19, count: 15),
        HourlyCheckIn(hour: 20, count: 9),
        HourlyCheckIn(hour: 21, count: 4),
      ],
      ticketTypeBreakdown: const [
        TicketTypeBreakdown(
          type: 'General Admission',
          sold: 40,
          checked: 30,
          revenueCents: 40000,
        ),
        TicketTypeBreakdown(
          type: 'VIP',
          sold: 13,
          checked: 8,
          revenueCents: 13000,
        ),
      ],
      peakCheckInTime: DateTime.now().copyWith(hour: 19, minute: 30),
      averageCheckInDurationSeconds: 4.2,
    );
  }
}
