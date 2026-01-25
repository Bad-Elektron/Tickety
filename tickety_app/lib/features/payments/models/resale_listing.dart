import '../../staff/models/ticket.dart';

/// Status of a resale listing.
enum ResaleListingStatus {
  active('active'),
  sold('sold'),
  cancelled('cancelled');

  final String value;
  const ResaleListingStatus(this.value);

  static ResaleListingStatus fromString(String value) {
    return ResaleListingStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => ResaleListingStatus.active,
    );
  }

  bool get isActive => this == active;
  bool get isSold => this == sold;
  bool get isCancelled => this == cancelled;
}

/// Represents a ticket listed for resale on the secondary market.
class ResaleListing {
  final String id;
  final String ticketId;
  final String sellerId;
  final int priceCents;
  final String currency;
  final ResaleListingStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The ticket being sold (joined data).
  final Ticket? ticket;

  /// Seller profile info (joined data).
  final Map<String, dynamic>? sellerProfile;

  const ResaleListing({
    required this.id,
    required this.ticketId,
    required this.sellerId,
    required this.priceCents,
    this.currency = 'usd',
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.ticket,
    this.sellerProfile,
  });

  /// Create ResaleListing from database JSON.
  factory ResaleListing.fromJson(Map<String, dynamic> json) {
    Ticket? ticket;
    if (json['tickets'] != null) {
      ticket = Ticket.fromJson(json['tickets'] as Map<String, dynamic>);
    }

    return ResaleListing(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      sellerId: json['seller_id'] as String,
      priceCents: json['price_cents'] as int,
      currency: json['currency'] as String? ?? 'usd',
      status: ResaleListingStatus.fromString(json['status'] as String? ?? 'active'),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      ticket: ticket,
      sellerProfile: json['profiles'] as Map<String, dynamic>?,
    );
  }

  /// Convert to JSON for database operations.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ticket_id': ticketId,
      'seller_id': sellerId,
      'price_cents': priceCents,
      'currency': currency,
      'status': status.value,
    };
  }

  /// Copy with modified fields.
  ResaleListing copyWith({
    String? id,
    String? ticketId,
    String? sellerId,
    int? priceCents,
    String? currency,
    ResaleListingStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    Ticket? ticket,
    Map<String, dynamic>? sellerProfile,
  }) {
    return ResaleListing(
      id: id ?? this.id,
      ticketId: ticketId ?? this.ticketId,
      sellerId: sellerId ?? this.sellerId,
      priceCents: priceCents ?? this.priceCents,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ticket: ticket ?? this.ticket,
      sellerProfile: sellerProfile ?? this.sellerProfile,
    );
  }

  /// Formatted listing price (e.g., "$49.99").
  String get formattedPrice {
    final dollars = priceCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Calculate platform fee (5% of listing price).
  int get platformFeeCents => (priceCents * 0.05).round();

  /// Calculate seller payout (95% of listing price).
  int get sellerPayoutCents => priceCents - platformFeeCents;

  /// Formatted platform fee.
  String get formattedPlatformFee {
    final dollars = platformFeeCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted seller payout.
  String get formattedSellerPayout {
    final dollars = sellerPayoutCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Total price for buyer (listing price + platform fee shown separately).
  /// Note: In some implementations, buyer pays listing price only,
  /// and platform fee comes from seller's portion.
  int get totalBuyerPriceCents => priceCents;

  /// Formatted total buyer price.
  String get formattedTotalBuyerPrice => formattedPrice;

  /// Event title from joined ticket data.
  String? get eventTitle => ticket?.eventData?['title'] as String?;

  /// Event date from joined ticket data.
  DateTime? get eventDate {
    final dateStr = ticket?.eventData?['date'] as String?;
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  /// Seller display name from joined profile data.
  String? get sellerName => sellerProfile?['full_name'] as String?;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResaleListing &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ResaleListing(id: $id, price: $formattedPrice, status: ${status.value})';
  }
}
