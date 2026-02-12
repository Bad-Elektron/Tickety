/// Status of a ticket offer.
enum TicketOfferStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  cancelled('cancelled'),
  expired('expired');

  const TicketOfferStatus(this.value);
  final String value;

  static TicketOfferStatus fromString(String? value) {
    if (value == null) return TicketOfferStatus.pending;
    return TicketOfferStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => TicketOfferStatus.pending,
    );
  }

  bool get isPending => this == pending;
  bool get isAccepted => this == accepted;
  bool get isDeclined => this == declined;
  bool get isCancelled => this == cancelled;
  bool get isExpired => this == expired;
  bool get isResolved => this != pending;
}

/// Ticket mode determines on-chain/off-chain behavior and resale eligibility.
enum TicketMode {
  standard('standard'),
  private_('private'),
  public_('public');

  const TicketMode(this.value);
  final String value;

  static TicketMode fromString(String? value) {
    if (value == null) return TicketMode.standard;
    return TicketMode.values.firstWhere(
      (m) => m.value == value,
      orElse: () => TicketMode.standard,
    );
  }

  bool get canResale => this != private_;

  String get displayLabel => switch (this) {
    standard => 'Standard',
    private_ => 'Private',
    public_ => 'Public',
  };
}

/// Represents a favor/comp ticket offer sent by an organizer.
class TicketOffer {
  final String id;
  final String eventId;
  final String organizerId;
  final String recipientEmail;
  final String? recipientUserId;
  final int priceCents;
  final String currency;
  final TicketMode ticketMode;
  final String? message;
  final TicketOfferStatus status;
  final String? ticketId;
  final String? ticketTypeId;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined data
  final String? eventTitle;
  final String? organizerName;

  const TicketOffer({
    required this.id,
    required this.eventId,
    required this.organizerId,
    required this.recipientEmail,
    this.recipientUserId,
    required this.priceCents,
    this.currency = 'USD',
    required this.ticketMode,
    this.message,
    required this.status,
    this.ticketId,
    this.ticketTypeId,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.eventTitle,
    this.organizerName,
  });

  factory TicketOffer.fromJson(Map<String, dynamic> json) {
    // Handle joined event data
    final events = json['events'] as Map<String, dynamic>?;

    return TicketOffer(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      organizerId: json['organizer_id'] as String,
      recipientEmail: json['recipient_email'] as String,
      recipientUserId: json['recipient_user_id'] as String?,
      priceCents: json['price_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'USD',
      ticketMode: TicketMode.fromString(json['ticket_mode'] as String?),
      message: json['message'] as String?,
      status: TicketOfferStatus.fromString(json['status'] as String?),
      ticketId: json['ticket_id'] as String?,
      ticketTypeId: json['ticket_type_id'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      eventTitle: events?['title'] as String?,
      organizerName: json['_organizer_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'organizer_id': organizerId,
      'recipient_email': recipientEmail,
      if (recipientUserId != null) 'recipient_user_id': recipientUserId,
      'price_cents': priceCents,
      'currency': currency,
      'ticket_mode': ticketMode.value,
      if (message != null) 'message': message,
      'status': status.value,
      if (ticketTypeId != null) 'ticket_type_id': ticketTypeId,
    };
  }

  TicketOffer copyWith({
    String? id,
    String? eventId,
    String? organizerId,
    String? recipientEmail,
    String? recipientUserId,
    int? priceCents,
    String? currency,
    TicketMode? ticketMode,
    String? message,
    TicketOfferStatus? status,
    String? ticketId,
    String? ticketTypeId,
    DateTime? expiresAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? eventTitle,
    String? organizerName,
  }) {
    return TicketOffer(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      organizerId: organizerId ?? this.organizerId,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      recipientUserId: recipientUserId ?? this.recipientUserId,
      priceCents: priceCents ?? this.priceCents,
      currency: currency ?? this.currency,
      ticketMode: ticketMode ?? this.ticketMode,
      message: message ?? this.message,
      status: status ?? this.status,
      ticketId: ticketId ?? this.ticketId,
      ticketTypeId: ticketTypeId ?? this.ticketTypeId,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      eventTitle: eventTitle ?? this.eventTitle,
      organizerName: organizerName ?? this.organizerName,
    );
  }

  bool get isFree => priceCents == 0;
  bool get isPaid => priceCents > 0;
  bool get isExpiredByDate =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  String get formattedPrice {
    if (priceCents == 0) return 'Free';
    final dollars = priceCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TicketOffer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
