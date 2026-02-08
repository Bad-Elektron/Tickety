/// Represents a saved card payment method from Stripe.
class PaymentMethodCard {
  final String id;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final bool isDefault;

  const PaymentMethodCard({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    this.isDefault = false,
  });

  factory PaymentMethodCard.fromJson(Map<String, dynamic> json) {
    return PaymentMethodCard(
      id: json['id'] as String,
      brand: json['brand'] as String? ?? 'unknown',
      last4: json['last4'] as String? ?? '****',
      expMonth: json['exp_month'] as int? ?? 0,
      expYear: json['exp_year'] as int? ?? 0,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  /// Display name for the card brand (e.g., "Visa", "Mastercard").
  String get displayBrand {
    switch (brand.toLowerCase()) {
      case 'visa':
        return 'Visa';
      case 'mastercard':
        return 'Mastercard';
      case 'amex':
        return 'Amex';
      case 'discover':
        return 'Discover';
      case 'diners':
        return 'Diners Club';
      case 'jcb':
        return 'JCB';
      case 'unionpay':
        return 'UnionPay';
      default:
        return brand[0].toUpperCase() + brand.substring(1);
    }
  }

  /// Formatted expiry string (e.g., "04/26").
  String get formattedExpiry {
    final month = expMonth.toString().padLeft(2, '0');
    final year = (expYear % 100).toString().padLeft(2, '0');
    return '$month/$year';
  }

  /// Whether the card is expired.
  bool get isExpired {
    final now = DateTime.now();
    if (expYear < now.year) return true;
    if (expYear == now.year && expMonth < now.month) return true;
    return false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentMethodCard &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'PaymentMethodCard($displayBrand ****$last4, exp $formattedExpiry${isDefault ? ', default' : ''})';
}

/// Response from creating a setup intent for adding a new card.
class SetupIntentResponse {
  final String clientSecret;
  final String ephemeralKey;
  final String customerId;
  final String setupIntentId;

  const SetupIntentResponse({
    required this.clientSecret,
    required this.ephemeralKey,
    required this.customerId,
    required this.setupIntentId,
  });

  factory SetupIntentResponse.fromJson(Map<String, dynamic> json) {
    return SetupIntentResponse(
      clientSecret: json['client_secret'] as String,
      ephemeralKey: json['ephemeral_key'] as String,
      customerId: json['customer_id'] as String,
      setupIntentId: json['setup_intent_id'] as String,
    );
  }
}
