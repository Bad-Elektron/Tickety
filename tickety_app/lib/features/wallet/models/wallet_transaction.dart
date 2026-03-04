/// Type of wallet transaction.
enum WalletTransactionType {
  achTopUp('ach_top_up'),
  achTopUpPending('ach_top_up_pending'),
  ticketPurchase('ticket_purchase'),
  refundCredit('refund_credit'),
  adminAdjustment('admin_adjustment');

  final String value;
  const WalletTransactionType(this.value);

  static WalletTransactionType fromString(String value) {
    return WalletTransactionType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => WalletTransactionType.achTopUp,
    );
  }

  /// Whether this is a credit (positive) transaction.
  bool get isCredit => this == achTopUp || this == achTopUpPending || this == refundCredit;

  /// Whether this is a debit (negative) transaction.
  bool get isDebit => this == ticketPurchase;

  /// Whether this transaction is still pending.
  bool get isPending => this == achTopUpPending;
}

/// Represents a single wallet transaction (credit or debit).
class WalletTransaction {
  final String id;
  final String userId;
  final WalletTransactionType type;
  final int amountCents;
  final int feeCents;
  final int balanceAfterCents;
  final String? stripePaymentIntentId;
  final String? paymentId;
  final String? description;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amountCents,
    this.feeCents = 0,
    required this.balanceAfterCents,
    this.stripePaymentIntentId,
    this.paymentId,
    this.description,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: WalletTransactionType.fromString(json['type'] as String? ?? 'ach_top_up'),
      amountCents: json['amount_cents'] as int,
      feeCents: json['fee_cents'] as int? ?? 0,
      balanceAfterCents: json['balance_after_cents'] as int,
      stripePaymentIntentId: json['stripe_payment_intent_id'] as String?,
      paymentId: json['payment_id'] as String?,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Formatted amount (e.g., "+$50.00" or "-$25.00").
  String get formattedAmount {
    final dollars = amountCents.abs() / 100;
    final prefix = amountCents >= 0 ? '+' : '-';
    return '$prefix\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted balance after transaction.
  String get formattedBalanceAfter {
    final dollars = balanceAfterCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted fee.
  String get formattedFee {
    final dollars = feeCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WalletTransaction &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
