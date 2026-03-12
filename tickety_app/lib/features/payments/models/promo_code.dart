/// Discount type for a promo code.
enum PromoDiscountType {
  percentage('percentage'),
  fixed('fixed');

  final String value;
  const PromoDiscountType(this.value);

  static PromoDiscountType fromString(String value) {
    return PromoDiscountType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => PromoDiscountType.percentage,
    );
  }
}

/// A promo code attached to an event.
class PromoCode {
  final String id;
  final String eventId;
  final String code;
  final PromoDiscountType discountType;
  final int discountValue;
  final int? maxUses;
  final int currentUses;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String? ticketTypeId;
  final bool isActive;
  final DateTime createdAt;

  const PromoCode({
    required this.id,
    required this.eventId,
    required this.code,
    required this.discountType,
    required this.discountValue,
    this.maxUses,
    this.currentUses = 0,
    this.validFrom,
    this.validUntil,
    this.ticketTypeId,
    this.isActive = true,
    required this.createdAt,
  });

  factory PromoCode.fromJson(Map<String, dynamic> json) {
    return PromoCode(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      code: json['code'] as String,
      discountType: PromoDiscountType.fromString(json['discount_type'] as String),
      discountValue: json['discount_value'] as int,
      maxUses: json['max_uses'] as int?,
      currentUses: json['current_uses'] as int? ?? 0,
      validFrom: json['valid_from'] != null
          ? DateTime.parse(json['valid_from'] as String)
          : null,
      validUntil: json['valid_until'] != null
          ? DateTime.parse(json['valid_until'] as String)
          : null,
      ticketTypeId: json['ticket_type_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Formatted discount display (e.g., "20% off" or "$5.00 off").
  String get formattedDiscount {
    if (discountType == PromoDiscountType.percentage) {
      return '$discountValue% off';
    }
    return '\$${(discountValue / 100).toStringAsFixed(2)} off';
  }

  /// Usage display (e.g., "12/50 used" or "12 used").
  String get formattedUsage {
    if (maxUses != null) {
      return '$currentUses/$maxUses used';
    }
    return '$currentUses used';
  }

  /// Whether the code has remaining uses.
  bool get hasRemainingUses =>
      maxUses == null || currentUses < maxUses!;
}

/// Result of validating a promo code.
class PromoValidationResult {
  final bool valid;
  final String? error;
  final String? promoCodeId;
  final String? discountType;
  final int? discountValue;
  final int? discountCents;
  final int? discountedPriceCents;

  const PromoValidationResult({
    required this.valid,
    this.error,
    this.promoCodeId,
    this.discountType,
    this.discountValue,
    this.discountCents,
    this.discountedPriceCents,
  });

  factory PromoValidationResult.fromJson(Map<String, dynamic> json) {
    return PromoValidationResult(
      valid: json['valid'] as bool? ?? false,
      error: json['error'] as String?,
      promoCodeId: json['promo_code_id'] as String?,
      discountType: json['discount_type'] as String?,
      discountValue: json['discount_value'] as int?,
      discountCents: json['discount_cents'] as int?,
      discountedPriceCents: json['discounted_price_cents'] as int?,
    );
  }
}
