import 'package:flutter/material.dart';

/// Merch provider type.
enum MerchProvider {
  shopify('shopify'),
  stripe('stripe'),
  none('none');

  const MerchProvider(this.value);
  final String value;

  static MerchProvider fromString(String? value) {
    return MerchProvider.values.firstWhere(
      (p) => p.value == value,
      orElse: () => MerchProvider.none,
    );
  }

  String get displayLabel => switch (this) {
    shopify => 'Shopify',
    stripe => 'Stripe Products',
    none => 'Not configured',
  };

  IconData get icon => switch (this) {
    shopify => Icons.shopping_bag,
    stripe => Icons.credit_card,
    none => Icons.settings,
  };
}

/// Organizer's merch store configuration.
@immutable
class OrganizerMerchConfig {
  final String id;
  final String organizerId;
  final MerchProvider provider;
  final String? shopifyDomain;
  final String? shopifyStorefrontToken;
  final bool isActive;

  const OrganizerMerchConfig({
    required this.id,
    required this.organizerId,
    this.provider = MerchProvider.none,
    this.shopifyDomain,
    this.shopifyStorefrontToken,
    this.isActive = false,
  });

  bool get isConfigured => provider != MerchProvider.none;
  bool get isShopify => provider == MerchProvider.shopify;
  bool get isStripe => provider == MerchProvider.stripe;

  factory OrganizerMerchConfig.fromJson(Map<String, dynamic> json) {
    return OrganizerMerchConfig(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      provider: MerchProvider.fromString(json['provider'] as String?),
      shopifyDomain: json['shopify_domain'] as String?,
      shopifyStorefrontToken: json['shopify_storefront_token'] as String?,
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'organizer_id': organizerId,
    'provider': provider.value,
    'shopify_domain': shopifyDomain,
    'shopify_storefront_token': shopifyStorefrontToken,
    'is_active': isActive,
  };

  OrganizerMerchConfig copyWith({
    MerchProvider? provider,
    String? shopifyDomain,
    String? shopifyStorefrontToken,
    bool? isActive,
  }) {
    return OrganizerMerchConfig(
      id: id,
      organizerId: organizerId,
      provider: provider ?? this.provider,
      shopifyDomain: shopifyDomain ?? this.shopifyDomain,
      shopifyStorefrontToken: shopifyStorefrontToken ?? this.shopifyStorefrontToken,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OrganizerMerchConfig && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
