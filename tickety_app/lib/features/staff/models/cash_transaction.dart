/// Status of a cash transaction.
enum CashTransactionStatus {
  pending('pending'),
  collected('collected'),
  disputed('disputed');

  const CashTransactionStatus(this.value);
  final String value;

  static CashTransactionStatus fromString(String? value) {
    return CashTransactionStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => CashTransactionStatus.pending,
    );
  }
}

/// Delivery method for cash sale tickets.
enum CashDeliveryMethod {
  nfc('nfc'),
  email('email'),
  inPerson('in_person');

  const CashDeliveryMethod(this.value);
  final String value;

  static CashDeliveryMethod fromString(String? value) {
    return CashDeliveryMethod.values.firstWhere(
      (s) => s.value == value,
      orElse: () => CashDeliveryMethod.inPerson,
    );
  }

  String get displayName {
    switch (this) {
      case CashDeliveryMethod.nfc:
        return 'NFC Transfer';
      case CashDeliveryMethod.email:
        return 'Email';
      case CashDeliveryMethod.inPerson:
        return 'In-Person';
    }
  }
}

/// Represents a cash transaction for a ticket sale.
class CashTransaction {
  final String id;
  final String eventId;
  final String sellerId;
  final String ticketId;
  final int amountCents;
  final int platformFeeCents;
  final String currency;
  final CashTransactionStatus status;
  final bool feeCharged;
  final String? feePaymentIntentId;
  final String? feeChargeError;
  final String? customerName;
  final String? customerEmail;
  final CashDeliveryMethod deliveryMethod;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? reconciledAt;
  final String? reconciledBy;

  // Joined seller data (optional)
  final String? sellerEmail;
  final String? sellerName;

  // Joined ticket data (optional)
  final String? ticketNumber;

  const CashTransaction({
    required this.id,
    required this.eventId,
    required this.sellerId,
    required this.ticketId,
    required this.amountCents,
    required this.platformFeeCents,
    required this.currency,
    required this.status,
    required this.feeCharged,
    this.feePaymentIntentId,
    this.feeChargeError,
    this.customerName,
    this.customerEmail,
    required this.deliveryMethod,
    required this.createdAt,
    required this.updatedAt,
    this.reconciledAt,
    this.reconciledBy,
    this.sellerEmail,
    this.sellerName,
    this.ticketNumber,
  });

  factory CashTransaction.fromJson(Map<String, dynamic> json) {
    // Handle nested profiles data for seller info
    final profilesData = json['profiles'] as Map<String, dynamic>?;
    // Handle nested ticket data
    final ticketData = json['tickets'] as Map<String, dynamic>?;

    return CashTransaction(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      sellerId: json['seller_id'] as String,
      ticketId: json['ticket_id'] as String,
      amountCents: json['amount_cents'] as int,
      platformFeeCents: json['platform_fee_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'USD',
      status: CashTransactionStatus.fromString(json['status'] as String?),
      feeCharged: json['fee_charged'] as bool? ?? false,
      feePaymentIntentId: json['fee_payment_intent_id'] as String?,
      feeChargeError: json['fee_charge_error'] as String?,
      customerName: json['customer_name'] as String?,
      customerEmail: json['customer_email'] as String?,
      deliveryMethod:
          CashDeliveryMethod.fromString(json['delivery_method'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      reconciledAt: json['reconciled_at'] != null
          ? DateTime.parse(json['reconciled_at'] as String)
          : null,
      reconciledBy: json['reconciled_by'] as String?,
      sellerEmail: profilesData?['email'] as String?,
      sellerName: profilesData?['display_name'] as String?,
      ticketNumber: ticketData?['ticket_number'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_id': eventId,
      'seller_id': sellerId,
      'ticket_id': ticketId,
      'amount_cents': amountCents,
      'platform_fee_cents': platformFeeCents,
      'currency': currency,
      'status': status.value,
      'fee_charged': feeCharged,
      'fee_payment_intent_id': feePaymentIntentId,
      'fee_charge_error': feeChargeError,
      'customer_name': customerName,
      'customer_email': customerEmail,
      'delivery_method': deliveryMethod.value,
    };
  }

  /// Formatted cash amount.
  String get formattedAmount {
    if (amountCents == 0) return 'Free';
    final dollars = amountCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted platform fee.
  String get formattedFee {
    final dollars = platformFeeCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Display name for the customer.
  String get customerDisplayName {
    if (customerName != null && customerName!.isNotEmpty) {
      return customerName!;
    }
    if (customerEmail != null && customerEmail!.isNotEmpty) {
      return customerEmail!;
    }
    return 'Anonymous';
  }

  /// Display name for the seller.
  String get sellerDisplayName {
    if (sellerName != null && sellerName!.isNotEmpty) {
      return sellerName!;
    }
    if (sellerEmail != null && sellerEmail!.isNotEmpty) {
      return sellerEmail!;
    }
    return 'Unknown Seller';
  }

  /// Whether the transaction has issues (fee not charged).
  bool get hasIssues => !feeCharged && platformFeeCents > 0;

  CashTransaction copyWith({
    String? id,
    String? eventId,
    String? sellerId,
    String? ticketId,
    int? amountCents,
    int? platformFeeCents,
    String? currency,
    CashTransactionStatus? status,
    bool? feeCharged,
    String? feePaymentIntentId,
    String? feeChargeError,
    String? customerName,
    String? customerEmail,
    CashDeliveryMethod? deliveryMethod,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? reconciledAt,
    String? reconciledBy,
    String? sellerEmail,
    String? sellerName,
    String? ticketNumber,
  }) {
    return CashTransaction(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      sellerId: sellerId ?? this.sellerId,
      ticketId: ticketId ?? this.ticketId,
      amountCents: amountCents ?? this.amountCents,
      platformFeeCents: platformFeeCents ?? this.platformFeeCents,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      feeCharged: feeCharged ?? this.feeCharged,
      feePaymentIntentId: feePaymentIntentId ?? this.feePaymentIntentId,
      feeChargeError: feeChargeError ?? this.feeChargeError,
      customerName: customerName ?? this.customerName,
      customerEmail: customerEmail ?? this.customerEmail,
      deliveryMethod: deliveryMethod ?? this.deliveryMethod,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reconciledAt: reconciledAt ?? this.reconciledAt,
      reconciledBy: reconciledBy ?? this.reconciledBy,
      sellerEmail: sellerEmail ?? this.sellerEmail,
      sellerName: sellerName ?? this.sellerName,
      ticketNumber: ticketNumber ?? this.ticketNumber,
    );
  }
}

/// Summary of cash transactions for an event.
class CashSummary {
  final int totalCashCents;
  final int totalFeesCents;
  final int feesCollectedCents;
  final int transactionCount;
  final int collectedCount;
  final int disputedCount;
  final int pendingCount;

  const CashSummary({
    required this.totalCashCents,
    required this.totalFeesCents,
    required this.feesCollectedCents,
    required this.transactionCount,
    required this.collectedCount,
    required this.disputedCount,
    required this.pendingCount,
  });

  factory CashSummary.fromJson(Map<String, dynamic> json) {
    return CashSummary(
      totalCashCents: (json['total_cash_cents'] as num?)?.toInt() ?? 0,
      totalFeesCents: (json['total_fees_cents'] as num?)?.toInt() ?? 0,
      feesCollectedCents: (json['fees_collected_cents'] as num?)?.toInt() ?? 0,
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
      collectedCount: (json['collected_count'] as num?)?.toInt() ?? 0,
      disputedCount: (json['disputed_count'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
    );
  }

  factory CashSummary.empty() {
    return const CashSummary(
      totalCashCents: 0,
      totalFeesCents: 0,
      feesCollectedCents: 0,
      transactionCount: 0,
      collectedCount: 0,
      disputedCount: 0,
      pendingCount: 0,
    );
  }

  String get formattedTotalCash {
    final dollars = totalCashCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  String get formattedTotalFees {
    final dollars = totalFeesCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  String get formattedFeesCollected {
    final dollars = feesCollectedCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  int get feesOutstandingCents => totalFeesCents - feesCollectedCents;

  String get formattedFeesOutstanding {
    final dollars = feesOutstandingCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }
}

/// Summary of cash transactions per seller.
class SellerCashSummary {
  final String sellerId;
  final String? sellerEmail;
  final int totalCashCents;
  final int totalFeesCents;
  final int transactionCount;
  final int collectedCount;
  final int pendingCount;

  const SellerCashSummary({
    required this.sellerId,
    this.sellerEmail,
    required this.totalCashCents,
    required this.totalFeesCents,
    required this.transactionCount,
    required this.collectedCount,
    required this.pendingCount,
  });

  factory SellerCashSummary.fromJson(Map<String, dynamic> json) {
    return SellerCashSummary(
      sellerId: json['seller_id'] as String,
      sellerEmail: json['seller_email'] as String?,
      totalCashCents: (json['total_cash_cents'] as num?)?.toInt() ?? 0,
      totalFeesCents: (json['total_fees_cents'] as num?)?.toInt() ?? 0,
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
      collectedCount: (json['collected_count'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
    );
  }

  String get formattedTotalCash {
    final dollars = totalCashCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  String get sellerDisplayName => sellerEmail ?? 'Unknown';
}
