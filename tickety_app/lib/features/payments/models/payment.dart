/// Status of a payment.
enum PaymentStatus {
  pending('pending'),
  processing('processing'),
  completed('completed'),
  failed('failed'),
  refunded('refunded');

  final String value;
  const PaymentStatus(this.value);

  static PaymentStatus fromString(String value) {
    return PaymentStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => PaymentStatus.pending,
    );
  }

  bool get isSuccessful => this == completed;
  bool get isFailed => this == failed;
  bool get isPending => this == pending || this == processing;
  bool get isRefunded => this == refunded;
}

/// Type of payment transaction.
enum PaymentType {
  primaryPurchase('primary_purchase'),
  resalePurchase('resale_purchase'),
  vendorPos('vendor_pos');

  final String value;
  const PaymentType(this.value);

  static PaymentType fromString(String value) {
    return PaymentType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => PaymentType.primaryPurchase,
    );
  }
}

/// Represents a payment transaction.
class Payment {
  final String id;
  final String userId;
  final String? ticketId;
  final String eventId;
  final int amountCents;
  final int platformFeeCents;
  final String currency;
  final PaymentStatus status;
  final PaymentType type;
  final String? stripePaymentIntentId;
  final String? stripeChargeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Additional metadata about the payment (event name, ticket number, etc.).
  final Map<String, dynamic>? metadata;

  const Payment({
    required this.id,
    required this.userId,
    this.ticketId,
    required this.eventId,
    required this.amountCents,
    this.platformFeeCents = 0,
    this.currency = 'usd',
    required this.status,
    required this.type,
    this.stripePaymentIntentId,
    this.stripeChargeId,
    required this.createdAt,
    required this.updatedAt,
    this.metadata,
  });

  /// Create Payment from database JSON.
  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      ticketId: json['ticket_id'] as String?,
      eventId: json['event_id'] as String,
      amountCents: json['amount_cents'] as int,
      platformFeeCents: json['platform_fee_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'usd',
      status: PaymentStatus.fromString(json['status'] as String? ?? 'pending'),
      type: PaymentType.fromString(json['type'] as String? ?? 'primary_purchase'),
      stripePaymentIntentId: json['stripe_payment_intent_id'] as String?,
      stripeChargeId: json['stripe_charge_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Convert to JSON for database operations.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'ticket_id': ticketId,
      'event_id': eventId,
      'amount_cents': amountCents,
      'platform_fee_cents': platformFeeCents,
      'currency': currency,
      'status': status.value,
      'type': type.value,
      'stripe_payment_intent_id': stripePaymentIntentId,
      'stripe_charge_id': stripeChargeId,
      'metadata': metadata,
    };
  }

  /// Copy with modified fields.
  Payment copyWith({
    String? id,
    String? userId,
    String? ticketId,
    String? eventId,
    int? amountCents,
    int? platformFeeCents,
    String? currency,
    PaymentStatus? status,
    PaymentType? type,
    String? stripePaymentIntentId,
    String? stripeChargeId,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return Payment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      ticketId: ticketId ?? this.ticketId,
      eventId: eventId ?? this.eventId,
      amountCents: amountCents ?? this.amountCents,
      platformFeeCents: platformFeeCents ?? this.platformFeeCents,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      type: type ?? this.type,
      stripePaymentIntentId: stripePaymentIntentId ?? this.stripePaymentIntentId,
      stripeChargeId: stripeChargeId ?? this.stripeChargeId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Formatted amount string (e.g., "$19.99").
  String get formattedAmount {
    final dollars = amountCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted platform fee string.
  String get formattedPlatformFee {
    final dollars = platformFeeCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// The seller's portion after platform fee.
  int get sellerAmountCents => amountCents - platformFeeCents;

  /// Formatted seller amount string.
  String get formattedSellerAmount {
    final dollars = sellerAmountCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Payment &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Payment(id: $id, amount: $formattedAmount, status: ${status.value})';
  }
}

/// Data needed to create a payment intent.
class CreatePaymentIntentRequest {
  final String eventId;
  final int amountCents;
  final String currency;
  final PaymentType type;
  final int quantity;
  final String? ticketId;
  final String? resaleListingId;
  final Map<String, dynamic>? metadata;

  const CreatePaymentIntentRequest({
    required this.eventId,
    required this.amountCents,
    this.currency = 'usd',
    required this.type,
    this.quantity = 1,
    this.ticketId,
    this.resaleListingId,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'amount_cents': amountCents,
      'currency': currency,
      'type': type.value,
      'quantity': quantity,
      if (ticketId != null) 'ticket_id': ticketId,
      if (resaleListingId != null) 'resale_listing_id': resaleListingId,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

/// Response from creating a payment intent.
class PaymentIntentResponse {
  final String paymentIntentId;
  final String clientSecret;
  final String? customerId;
  final String? ephemeralKey;
  final String? paymentId;

  const PaymentIntentResponse({
    required this.paymentIntentId,
    required this.clientSecret,
    this.customerId,
    this.ephemeralKey,
    this.paymentId,
  });

  factory PaymentIntentResponse.fromJson(Map<String, dynamic> json) {
    return PaymentIntentResponse(
      paymentIntentId: json['payment_intent_id'] as String,
      clientSecret: json['client_secret'] as String,
      customerId: json['customer_id'] as String?,
      ephemeralKey: json['ephemeral_key'] as String?,
      paymentId: json['payment_id'] as String?,
    );
  }
}
