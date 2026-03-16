import 'package:flutter/material.dart';

/// Status lifecycle of a merch order.
enum MerchOrderStatus {
  pending('pending'),
  paid('paid'),
  processing('processing'),
  shipped('shipped'),
  delivered('delivered'),
  cancelled('cancelled'),
  refunded('refunded');

  const MerchOrderStatus(this.value);
  final String value;

  static MerchOrderStatus fromString(String? value) {
    return MerchOrderStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => MerchOrderStatus.pending,
    );
  }

  String get displayLabel => switch (this) {
    pending => 'Pending',
    paid => 'Paid',
    processing => 'Processing',
    shipped => 'Shipped',
    delivered => 'Delivered',
    cancelled => 'Cancelled',
    refunded => 'Refunded',
  };

  Color get color => switch (this) {
    pending => const Color(0xFFFF9800),
    paid => const Color(0xFF2196F3),
    processing => const Color(0xFF9C27B0),
    shipped => const Color(0xFF00BCD4),
    delivered => const Color(0xFF4CAF50),
    cancelled => const Color(0xFF9E9E9E),
    refunded => const Color(0xFFF44336),
  };

  bool get isActive => this == pending || this == paid || this == processing || this == shipped;
}

/// Shipping address for merch orders.
@immutable
class ShippingAddress {
  final String name;
  final String line1;
  final String? line2;
  final String city;
  final String state;
  final String postalCode;
  final String country;

  const ShippingAddress({
    required this.name,
    required this.line1,
    this.line2,
    required this.city,
    required this.state,
    required this.postalCode,
    this.country = 'US',
  });

  factory ShippingAddress.fromJson(Map<String, dynamic> json) {
    return ShippingAddress(
      name: json['name'] as String? ?? '',
      line1: json['line1'] as String? ?? '',
      line2: json['line2'] as String?,
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      postalCode: json['postal_code'] as String? ?? '',
      country: json['country'] as String? ?? 'US',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'line1': line1,
    if (line2 != null) 'line2': line2,
    'city': city,
    'state': state,
    'postal_code': postalCode,
    'country': country,
  };

  String get formatted {
    final parts = [line1];
    if (line2 != null && line2!.isNotEmpty) parts.add(line2!);
    parts.add('$city, $state $postalCode');
    if (country != 'US') parts.add(country);
    return parts.join('\n');
  }
}

/// A merch order placed by a buyer.
@immutable
class MerchOrder {
  final String id;
  final String userId;
  final String organizerId;
  final String productId;
  final String? variantId;
  final int quantity;
  final int amountCents;
  final MerchOrderStatus status;
  final ShippingAddress? shippingAddress;
  final Map<String, dynamic>? trackingInfo;
  final String fulfillmentType;
  final String? stripePaymentIntentId;
  final String? shopifyCheckoutUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined data
  final String? productTitle;
  final String? productImageUrl;
  final String? variantName;

  const MerchOrder({
    required this.id,
    required this.userId,
    required this.organizerId,
    required this.productId,
    this.variantId,
    this.quantity = 1,
    required this.amountCents,
    required this.status,
    this.shippingAddress,
    this.trackingInfo,
    this.fulfillmentType = 'ship',
    this.stripePaymentIntentId,
    this.shopifyCheckoutUrl,
    required this.createdAt,
    required this.updatedAt,
    this.productTitle,
    this.productImageUrl,
    this.variantName,
  });

  String get formattedAmount {
    final dollars = amountCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  String? get trackingNumber => trackingInfo?['tracking_number'] as String?;
  String? get trackingUrl => trackingInfo?['tracking_url'] as String?;
  String? get carrier => trackingInfo?['carrier'] as String?;

  factory MerchOrder.fromJson(Map<String, dynamic> json) {
    final shippingRaw = json['shipping_address'];
    final trackingRaw = json['tracking_info'];
    final product = json['merch_products'] as Map<String, dynamic>?;
    final variant = json['merch_variants'] as Map<String, dynamic>?;

    final imageUrls = product?['image_urls'];
    String? firstImage;
    if (imageUrls is List && imageUrls.isNotEmpty) {
      firstImage = imageUrls.first as String?;
    }

    return MerchOrder(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      organizerId: json['organizer_id'] as String,
      productId: json['product_id'] as String,
      variantId: json['variant_id'] as String?,
      quantity: json['quantity'] as int? ?? 1,
      amountCents: json['amount_cents'] as int,
      status: MerchOrderStatus.fromString(json['status'] as String?),
      shippingAddress: shippingRaw is Map<String, dynamic>
          ? ShippingAddress.fromJson(shippingRaw)
          : null,
      trackingInfo: trackingRaw is Map<String, dynamic> ? trackingRaw : null,
      fulfillmentType: json['fulfillment_type'] as String? ?? 'ship',
      stripePaymentIntentId: json['stripe_payment_intent_id'] as String?,
      shopifyCheckoutUrl: json['shopify_checkout_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      productTitle: product?['title'] as String?,
      productImageUrl: firstImage,
      variantName: variant?['name'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MerchOrder && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
