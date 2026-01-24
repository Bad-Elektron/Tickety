/// Represents a sold ticket.
class Ticket {
  final String id;
  final String eventId;
  final String ticketNumber;
  final String? ownerEmail;
  final String? ownerName;
  final String? ownerUserId;
  final String? ownerWalletAddress;
  final int pricePaidCents;
  final String currency;
  final String? soldBy;
  final DateTime soldAt;
  final DateTime? checkedInAt;
  final String? checkedInBy;
  final bool nftMinted;
  final String? nftAssetId;
  final DateTime? nftMintedAt;
  final TicketStatus status;
  final DateTime createdAt;

  /// Event data from join (only populated by getMyTickets).
  final Map<String, dynamic>? eventData;

  const Ticket({
    required this.id,
    required this.eventId,
    required this.ticketNumber,
    this.ownerEmail,
    this.ownerName,
    this.ownerUserId,
    this.ownerWalletAddress,
    required this.pricePaidCents,
    required this.currency,
    this.soldBy,
    required this.soldAt,
    this.checkedInAt,
    this.checkedInBy,
    required this.nftMinted,
    this.nftAssetId,
    this.nftMintedAt,
    required this.status,
    required this.createdAt,
    this.eventData,
  });

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      ticketNumber: json['ticket_number'] as String,
      ownerEmail: json['owner_email'] as String?,
      ownerName: json['owner_name'] as String?,
      ownerUserId: json['owner_user_id'] as String?,
      ownerWalletAddress: json['owner_wallet_address'] as String?,
      pricePaidCents: json['price_paid_cents'] as int,
      currency: json['currency'] as String? ?? 'USD',
      soldBy: json['sold_by'] as String?,
      soldAt: DateTime.parse(json['sold_at'] as String),
      checkedInAt: json['checked_in_at'] != null
          ? DateTime.parse(json['checked_in_at'] as String)
          : null,
      checkedInBy: json['checked_in_by'] as String?,
      nftMinted: json['nft_minted'] as bool? ?? false,
      nftAssetId: json['nft_asset_id'] as String?,
      nftMintedAt: json['nft_minted_at'] != null
          ? DateTime.parse(json['nft_minted_at'] as String)
          : null,
      status: TicketStatus.fromString(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
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
    };
  }

  String get formattedPrice {
    final dollars = pricePaidCents / 100;
    return '\$$dollars';
  }

  bool get isUsed => status == TicketStatus.used || checkedInAt != null;
  bool get isValid => status == TicketStatus.valid;
}

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
