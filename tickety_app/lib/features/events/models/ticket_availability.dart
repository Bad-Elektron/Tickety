/// Represents ticket availability for an event.
///
/// Uses SQL aggregation to get counts without fetching all records.
class TicketAvailability {
  /// Maximum tickets for the event. Null means unlimited.
  final int? maxTickets;

  /// Number of tickets already sold.
  final int soldCount;

  /// Number of tickets still available. Null if unlimited.
  final int? available;

  /// Number of resale tickets available.
  final int resaleCount;

  const TicketAvailability({
    this.maxTickets,
    required this.soldCount,
    this.available,
    this.resaleCount = 0,
  });

  /// Whether tickets are limited (has a max).
  bool get isLimited => maxTickets != null;

  /// Whether official tickets are available.
  bool get hasOfficialTickets => available == null || available! > 0;

  /// Whether resale tickets are available.
  bool get hasResaleTickets => resaleCount > 0;

  /// Formatted availability string for official tickets.
  String get officialAvailabilityText {
    if (maxTickets == null) {
      return 'Available';
    }
    return '$available of $maxTickets remaining';
  }

  /// Formatted availability string for resale tickets.
  String get resaleAvailabilityText {
    if (resaleCount == 0) {
      return 'None available';
    }
    return '$resaleCount available';
  }

  factory TicketAvailability.fromJson(
    Map<String, dynamic> json, {
    int resaleCount = 0,
  }) {
    return TicketAvailability(
      maxTickets: json['max_tickets'] as int?,
      soldCount: json['sold_count'] as int? ?? 0,
      available: json['available'] as int?,
      resaleCount: resaleCount,
    );
  }

  TicketAvailability copyWith({
    int? maxTickets,
    int? soldCount,
    int? available,
    int? resaleCount,
  }) {
    return TicketAvailability(
      maxTickets: maxTickets ?? this.maxTickets,
      soldCount: soldCount ?? this.soldCount,
      available: available ?? this.available,
      resaleCount: resaleCount ?? this.resaleCount,
    );
  }
}
