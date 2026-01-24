import 'package:flutter/material.dart';

/// Represents a ticket for an event.
@immutable
class TicketModel {
  final String id;
  final String eventId;
  final String eventTitle;
  final String? eventSubtitle;
  final String holderName;
  final String holderEmail;
  final String ticketType;
  final DateTime purchaseDate;
  final DateTime eventDate;
  final TimeOfDay? eventTime;
  final String? venue;
  final String? city;
  final String? country;
  final double? latitude;
  final double? longitude;
  final bool isRedeemed;
  final DateTime? redeemedAt;
  final String? seatInfo;
  final int? priceInCents;
  final String currency;
  final bool isListedForSale;
  final int? listingPriceInCents;
  final int noiseSeed;

  const TicketModel({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    this.eventSubtitle,
    required this.holderName,
    required this.holderEmail,
    required this.ticketType,
    required this.purchaseDate,
    required this.eventDate,
    this.eventTime,
    this.venue,
    this.city,
    this.country,
    this.latitude,
    this.longitude,
    this.isRedeemed = false,
    this.redeemedAt,
    this.seatInfo,
    this.priceInCents,
    this.currency = 'USD',
    this.isListedForSale = false,
    this.listingPriceInCents,
    this.noiseSeed = 42,
  });

  /// Combines venue and city for display.
  String? get displayLocation {
    if (venue != null && city != null) {
      return '$venue, $city';
    }
    if (venue != null) return venue;
    if (city != null) return city;
    return null;
  }

  /// Full address for navigation.
  String? get fullAddress {
    final parts = <String>[];
    if (venue != null) parts.add(venue!);
    if (city != null) parts.add(city!);
    if (country != null) parts.add(country!);
    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  /// Whether location coordinates are available.
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Formatted event time string.
  String? get formattedTime {
    if (eventTime == null) return null;
    final hour = eventTime!.hourOfPeriod == 0 ? 12 : eventTime!.hourOfPeriod;
    final minute = eventTime!.minute.toString().padLeft(2, '0');
    final period = eventTime!.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  /// Formatted original price.
  String get formattedPrice {
    if (priceInCents == null || priceInCents == 0) return 'Free';
    final dollars = priceInCents! / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted listing price.
  String? get formattedListingPrice {
    if (listingPriceInCents == null) return null;
    final dollars = listingPriceInCents! / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Creates a copy with modified properties.
  TicketModel copyWith({
    String? id,
    String? eventId,
    String? eventTitle,
    String? eventSubtitle,
    String? holderName,
    String? holderEmail,
    String? ticketType,
    DateTime? purchaseDate,
    DateTime? eventDate,
    TimeOfDay? eventTime,
    String? venue,
    String? city,
    String? country,
    double? latitude,
    double? longitude,
    bool? isRedeemed,
    DateTime? redeemedAt,
    String? seatInfo,
    int? priceInCents,
    String? currency,
    bool? isListedForSale,
    int? listingPriceInCents,
    int? noiseSeed,
  }) {
    return TicketModel(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      eventTitle: eventTitle ?? this.eventTitle,
      eventSubtitle: eventSubtitle ?? this.eventSubtitle,
      holderName: holderName ?? this.holderName,
      holderEmail: holderEmail ?? this.holderEmail,
      ticketType: ticketType ?? this.ticketType,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      eventDate: eventDate ?? this.eventDate,
      eventTime: eventTime ?? this.eventTime,
      venue: venue ?? this.venue,
      city: city ?? this.city,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isRedeemed: isRedeemed ?? this.isRedeemed,
      redeemedAt: redeemedAt ?? this.redeemedAt,
      seatInfo: seatInfo ?? this.seatInfo,
      priceInCents: priceInCents ?? this.priceInCents,
      currency: currency ?? this.currency,
      isListedForSale: isListedForSale ?? this.isListedForSale,
      listingPriceInCents: listingPriceInCents ?? this.listingPriceInCents,
      noiseSeed: noiseSeed ?? this.noiseSeed,
    );
  }

  /// Validation status for this ticket.
  TicketValidationStatus get validationStatus {
    if (isRedeemed) {
      return TicketValidationStatus.alreadyRedeemed;
    }
    if (eventDate.isBefore(DateTime.now().subtract(const Duration(hours: 6)))) {
      return TicketValidationStatus.eventPassed;
    }
    return TicketValidationStatus.valid;
  }
}

/// Validation status for scanned tickets.
enum TicketValidationStatus {
  valid(
    label: 'Valid Ticket',
    icon: Icons.check_circle,
    color: Color(0xFF4CAF50),
  ),
  alreadyRedeemed(
    label: 'Already Redeemed',
    icon: Icons.cancel,
    color: Color(0xFFF44336),
  ),
  eventPassed(
    label: 'Event Has Passed',
    icon: Icons.event_busy,
    color: Color(0xFFFF9800),
  ),
  invalidTicket(
    label: 'Invalid Ticket',
    icon: Icons.error,
    color: Color(0xFFF44336),
  ),
  wrongEvent(
    label: 'Wrong Event',
    icon: Icons.event_note,
    color: Color(0xFFFF9800),
  );

  const TicketValidationStatus({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

/// Placeholder ticket data for development.
abstract class PlaceholderTickets {
  /// Tickets for event admin/usher view.
  static final List<TicketModel> forEvent = [
    TicketModel(
      id: 'tkt_001',
      eventId: 'my_evt_001',
      eventTitle: 'Birthday Bash 2025',
      holderName: 'John Smith',
      holderEmail: 'john.smith@email.com',
      ticketType: 'General Admission',
      purchaseDate: DateTime.now().subtract(const Duration(days: 5)),
      eventDate: DateTime.now().add(const Duration(days: 21)),
      eventTime: const TimeOfDay(hour: 19, minute: 0),
      venue: 'Grand Ballroom',
      city: 'Miami',
      country: 'USA',
      priceInCents: 5000,
      noiseSeed: 101,
    ),
    TicketModel(
      id: 'tkt_002',
      eventId: 'my_evt_001',
      eventTitle: 'Birthday Bash 2025',
      holderName: 'Sarah Johnson',
      holderEmail: 'sarah.j@email.com',
      ticketType: 'VIP',
      purchaseDate: DateTime.now().subtract(const Duration(days: 3)),
      eventDate: DateTime.now().add(const Duration(days: 21)),
      eventTime: const TimeOfDay(hour: 19, minute: 0),
      venue: 'Grand Ballroom',
      city: 'Miami',
      country: 'USA',
      seatInfo: 'Table 3',
      priceInCents: 15000,
      noiseSeed: 101,
    ),
    TicketModel(
      id: 'tkt_003',
      eventId: 'my_evt_001',
      eventTitle: 'Birthday Bash 2025',
      holderName: 'Mike Wilson',
      holderEmail: 'mike.w@email.com',
      ticketType: 'General Admission',
      purchaseDate: DateTime.now().subtract(const Duration(days: 1)),
      eventDate: DateTime.now().add(const Duration(days: 21)),
      eventTime: const TimeOfDay(hour: 19, minute: 0),
      venue: 'Grand Ballroom',
      city: 'Miami',
      country: 'USA',
      isRedeemed: true,
      redeemedAt: DateTime.now().subtract(const Duration(hours: 2)),
      priceInCents: 5000,
      noiseSeed: 101,
    ),
  ];

  /// User's own purchased tickets.
  static final List<TicketModel> myTickets = [
    TicketModel(
      id: 'my_tkt_001',
      eventId: 'evt_001',
      eventTitle: 'Summer Music Festival',
      eventSubtitle: 'Three days of incredible live performances',
      holderName: 'Guest User',
      holderEmail: 'guest@tickety.app',
      ticketType: 'General Admission',
      purchaseDate: DateTime.now().subtract(const Duration(days: 7)),
      eventDate: DateTime.now().add(const Duration(days: 14)),
      eventTime: const TimeOfDay(hour: 16, minute: 0),
      venue: 'Central Park',
      city: 'New York',
      country: 'USA',
      latitude: 40.7829,
      longitude: -73.9654,
      priceInCents: 7500,
      noiseSeed: 42,
    ),
    TicketModel(
      id: 'my_tkt_002',
      eventId: 'evt_003',
      eventTitle: 'Food & Wine Expo',
      eventSubtitle: 'A culinary journey around the world',
      holderName: 'Guest User',
      holderEmail: 'guest@tickety.app',
      ticketType: 'VIP Access',
      purchaseDate: DateTime.now().subtract(const Duration(days: 3)),
      eventDate: DateTime.now().add(const Duration(days: 7)),
      eventTime: const TimeOfDay(hour: 18, minute: 30),
      venue: 'Grand Hall',
      city: 'Chicago',
      country: 'USA',
      latitude: 41.8781,
      longitude: -87.6298,
      seatInfo: 'Priority Entry',
      priceInCents: 8500,
      noiseSeed: 256,
    ),
    TicketModel(
      id: 'my_tkt_003',
      eventId: 'evt_006',
      eventTitle: 'Broadway Musical Night',
      eventSubtitle: 'A spectacular showcase of Broadway hits',
      holderName: 'Guest User',
      holderEmail: 'guest@tickety.app',
      ticketType: 'Orchestra',
      purchaseDate: DateTime.now().subtract(const Duration(days: 14)),
      eventDate: DateTime.now().add(const Duration(days: 10)),
      eventTime: const TimeOfDay(hour: 20, minute: 0),
      venue: 'Lincoln Center',
      city: 'New York',
      country: 'USA',
      latitude: 40.7725,
      longitude: -73.9835,
      seatInfo: 'Row G, Seat 14',
      priceInCents: 12000,
      noiseSeed: 333,
    ),
  ];
}
