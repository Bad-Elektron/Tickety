import 'package:flutter/material.dart';

import '../../favor_tickets/models/ticket_offer.dart';

/// Core ticket status - mutually exclusive states.
enum TicketStatus {
  valid('valid'),
  used('used'),
  cancelled('cancelled'),
  refunded('refunded');

  const TicketStatus(this.value);
  final String value;

  static TicketStatus fromString(String? value) {
    return TicketStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => TicketStatus.valid,
    );
  }
}

/// Resale listing status - mutually exclusive states.
enum ListingStatus {
  none('none'),
  listed('listed'),
  sold('sold'),
  cancelled('cancelled');

  const ListingStatus(this.value);
  final String value;

  static ListingStatus fromString(String? value) {
    if (value == null) return ListingStatus.none;
    return ListingStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => ListingStatus.none,
    );
  }
}

/// Validation result for ticket scanning/check-in.
///
/// This is computed from ticket state, not stored.
enum TicketValidationResult {
  valid(
    label: 'Valid Ticket',
    icon: Icons.check_circle,
    color: Color(0xFF4CAF50),
  ),
  alreadyUsed(
    label: 'Already Used',
    icon: Icons.cancel,
    color: Color(0xFFF44336),
  ),
  eventPassed(
    label: 'Event Has Passed',
    icon: Icons.event_busy,
    color: Color(0xFFFF9800),
  ),
  cancelled(
    label: 'Ticket Cancelled',
    icon: Icons.block,
    color: Color(0xFFF44336),
  ),
  refunded(
    label: 'Ticket Refunded',
    icon: Icons.money_off,
    color: Color(0xFFFF9800),
  );

  const TicketValidationResult({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

/// Represents a ticket for an event.
///
/// This is the single source of truth for ticket data, used across
/// staff operations, user display, and resale features.
class Ticket {
  // ─────────────────────────────────────────────────────────────────
  // Core identification
  // ─────────────────────────────────────────────────────────────────
  final String id;
  final String eventId;
  final String ticketNumber;
  final DateTime createdAt;

  // ─────────────────────────────────────────────────────────────────
  // Owner information
  // ─────────────────────────────────────────────────────────────────
  final String? ownerEmail;
  final String? ownerName;
  final String? ownerUserId;
  final String? ownerWalletAddress;

  // ─────────────────────────────────────────────────────────────────
  // Purchase & pricing
  // ─────────────────────────────────────────────────────────────────
  final int pricePaidCents;
  final String currency;
  final String? soldBy;
  final DateTime soldAt;

  // ─────────────────────────────────────────────────────────────────
  // Status (enum-based)
  // ─────────────────────────────────────────────────────────────────
  final TicketStatus status;

  // ─────────────────────────────────────────────────────────────────
  // Check-in tracking
  // ─────────────────────────────────────────────────────────────────
  final DateTime? checkedInAt;
  final String? checkedInBy;

  // ─────────────────────────────────────────────────────────────────
  // NFT integration
  // ─────────────────────────────────────────────────────────────────
  final bool nftMinted;
  final String? nftAssetId;
  final DateTime? nftMintedAt;

  // ─────────────────────────────────────────────────────────────────
  // Ticket mode (standard/private/public)
  // ─────────────────────────────────────────────────────────────────
  final TicketMode ticketMode;

  // ─────────────────────────────────────────────────────────────────
  // Resale listing (enum-based)
  // ─────────────────────────────────────────────────────────────────
  final ListingStatus listingStatus;
  final int? listingPriceCents;

  // ─────────────────────────────────────────────────────────────────
  // Event data (populated via JOIN queries)
  // ─────────────────────────────────────────────────────────────────
  final Map<String, dynamic>? eventData;

  const Ticket({
    required this.id,
    required this.eventId,
    required this.ticketNumber,
    required this.createdAt,
    this.ownerEmail,
    this.ownerName,
    this.ownerUserId,
    this.ownerWalletAddress,
    required this.pricePaidCents,
    required this.currency,
    this.soldBy,
    required this.soldAt,
    required this.status,
    this.checkedInAt,
    this.checkedInBy,
    required this.nftMinted,
    this.nftAssetId,
    this.nftMintedAt,
    this.ticketMode = TicketMode.standard,
    this.listingStatus = ListingStatus.none,
    this.listingPriceCents,
    this.eventData,
  });

  // ─────────────────────────────────────────────────────────────────
  // JSON serialization
  // ─────────────────────────────────────────────────────────────────

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      ticketNumber: json['ticket_number'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      ownerEmail: json['owner_email'] as String?,
      ownerName: json['owner_name'] as String?,
      ownerUserId: json['owner_user_id'] as String?,
      ownerWalletAddress: json['owner_wallet_address'] as String?,
      pricePaidCents: json['price_paid_cents'] as int,
      currency: json['currency'] as String? ?? 'USD',
      soldBy: json['sold_by'] as String?,
      soldAt: DateTime.parse(json['sold_at'] as String),
      status: TicketStatus.fromString(json['status'] as String?),
      checkedInAt: json['checked_in_at'] != null
          ? DateTime.parse(json['checked_in_at'] as String)
          : null,
      checkedInBy: json['checked_in_by'] as String?,
      nftMinted: json['nft_minted'] as bool? ?? false,
      nftAssetId: json['nft_asset_id'] as String?,
      nftMintedAt: json['nft_minted_at'] != null
          ? DateTime.parse(json['nft_minted_at'] as String)
          : null,
      ticketMode: TicketMode.fromString(json['ticket_mode'] as String?),
      listingStatus: ListingStatus.fromString(json['listing_status'] as String?),
      listingPriceCents: json['listing_price_cents'] as int?,
      eventData: json['events'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'ticket_number': ticketNumber,
      'owner_email': ownerEmail,
      'owner_name': ownerName,
      'owner_user_id': ownerUserId,
      'owner_wallet_address': ownerWalletAddress,
      'price_paid_cents': pricePaidCents,
      'currency': currency,
      'sold_by': soldBy,
      'status': status.value,
      'ticket_mode': ticketMode.value,
      'listing_status': listingStatus.value,
      if (listingPriceCents != null) 'listing_price_cents': listingPriceCents,
    };
  }

  // ─────────────────────────────────────────────────────────────────
  // Status-based computed properties
  // ─────────────────────────────────────────────────────────────────

  /// Whether ticket has been used (checked in).
  bool get isUsed => status == TicketStatus.used;

  /// Whether ticket is valid and can be used.
  bool get isValid => status == TicketStatus.valid;

  /// Whether ticket was cancelled.
  bool get isCancelled => status == TicketStatus.cancelled;

  /// Whether ticket was refunded.
  bool get isRefunded => status == TicketStatus.refunded;

  /// Whether ticket is currently listed for resale.
  bool get isListedForSale => listingStatus == ListingStatus.listed;

  /// Whether ticket can be listed for resale.
  bool get canBeResold => ticketMode.canResale && isValid && !isListedForSale;

  // ─────────────────────────────────────────────────────────────────
  // Validation for check-in (computed, not stored)
  // ─────────────────────────────────────────────────────────────────

  /// Validates ticket for check-in, considering status and event date.
  TicketValidationResult validate({DateTime? eventDate}) {
    // Check status first
    switch (status) {
      case TicketStatus.used:
        return TicketValidationResult.alreadyUsed;
      case TicketStatus.cancelled:
        return TicketValidationResult.cancelled;
      case TicketStatus.refunded:
        return TicketValidationResult.refunded;
      case TicketStatus.valid:
        // Check if event has passed (6 hour grace period)
        final checkDate = eventDate ?? this.eventDate;
        if (checkDate != null) {
          final cutoff = checkDate.add(const Duration(hours: 6));
          if (DateTime.now().isAfter(cutoff)) {
            return TicketValidationResult.eventPassed;
          }
        }
        return TicketValidationResult.valid;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Event data accessors (from JOIN)
  // ─────────────────────────────────────────────────────────────────

  /// Event title from joined data.
  String get eventTitle =>
      eventData?['title'] as String? ?? 'Unknown Event';

  /// Event date from joined data.
  DateTime? get eventDate {
    final dateStr = eventData?['date'] as String?;
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  /// Event venue from joined data.
  String? get venue => eventData?['venue'] as String?;

  /// Event city from joined data.
  String? get city => eventData?['city'] as String?;

  /// Event country from joined data.
  String? get country => eventData?['country'] as String?;

  /// Noise seed for visual styling.
  int get noiseSeed =>
      eventData?['noise_seed'] as int? ?? ticketNumber.hashCode;

  /// Ticket type (e.g., "General Admission", "VIP").
  String get ticketType =>
      eventData?['ticket_type'] as String? ?? 'General Admission';

  /// Combined venue and city for display.
  String? get displayLocation {
    if (venue != null && city != null) return '$venue, $city';
    return venue ?? city;
  }

  /// Full address for navigation.
  String? get fullAddress {
    final parts = <String>[];
    if (venue != null) parts.add(venue!);
    if (city != null) parts.add(city!);
    if (country != null) parts.add(country!);
    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  // ─────────────────────────────────────────────────────────────────
  // Price formatting
  // ─────────────────────────────────────────────────────────────────

  /// Formatted purchase price.
  String get formattedPrice {
    if (pricePaidCents == 0) return 'Free';
    final dollars = pricePaidCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted listing price for resale.
  String? get formattedListingPrice {
    if (listingPriceCents == null) return null;
    final dollars = listingPriceCents! / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  // ─────────────────────────────────────────────────────────────────
  // Copy with modifications
  // ─────────────────────────────────────────────────────────────────

  Ticket copyWith({
    String? id,
    String? eventId,
    String? ticketNumber,
    DateTime? createdAt,
    String? ownerEmail,
    String? ownerName,
    String? ownerUserId,
    String? ownerWalletAddress,
    int? pricePaidCents,
    String? currency,
    String? soldBy,
    DateTime? soldAt,
    TicketStatus? status,
    DateTime? checkedInAt,
    String? checkedInBy,
    bool? nftMinted,
    String? nftAssetId,
    DateTime? nftMintedAt,
    TicketMode? ticketMode,
    ListingStatus? listingStatus,
    int? listingPriceCents,
    Map<String, dynamic>? eventData,
  }) {
    return Ticket(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      ticketNumber: ticketNumber ?? this.ticketNumber,
      createdAt: createdAt ?? this.createdAt,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      ownerName: ownerName ?? this.ownerName,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      ownerWalletAddress: ownerWalletAddress ?? this.ownerWalletAddress,
      pricePaidCents: pricePaidCents ?? this.pricePaidCents,
      currency: currency ?? this.currency,
      soldBy: soldBy ?? this.soldBy,
      soldAt: soldAt ?? this.soldAt,
      status: status ?? this.status,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      checkedInBy: checkedInBy ?? this.checkedInBy,
      nftMinted: nftMinted ?? this.nftMinted,
      nftAssetId: nftAssetId ?? this.nftAssetId,
      nftMintedAt: nftMintedAt ?? this.nftMintedAt,
      ticketMode: ticketMode ?? this.ticketMode,
      listingStatus: listingStatus ?? this.listingStatus,
      listingPriceCents: listingPriceCents ?? this.listingPriceCents,
      eventData: eventData ?? this.eventData,
    );
  }
}
