import 'package:flutter/material.dart';

import 'merch_variant.dart';

/// Fulfillment type for a merch product.
enum FulfillmentType {
  ship('ship'),
  pickup('pickup');

  const FulfillmentType(this.value);
  final String value;

  static FulfillmentType fromString(String? value) {
    return FulfillmentType.values.firstWhere(
      (f) => f.value == value,
      orElse: () => FulfillmentType.ship,
    );
  }
}

/// A physical merchandise product sold by an organizer.
@immutable
class MerchProduct {
  final String id;
  final String organizerId;
  final String source; // 'shopify' or 'stripe'
  final String? externalId;
  final String title;
  final String? description;
  final List<String> imageUrls;
  final int basePriceCents;
  final bool isActive;
  final String? eventId;
  final FulfillmentType fulfillmentType;
  final List<MerchVariant> variants;
  final DateTime createdAt;

  const MerchProduct({
    required this.id,
    required this.organizerId,
    required this.source,
    this.externalId,
    required this.title,
    this.description,
    this.imageUrls = const [],
    required this.basePriceCents,
    this.isActive = true,
    this.eventId,
    this.fulfillmentType = FulfillmentType.ship,
    this.variants = const [],
    required this.createdAt,
  });

  /// Formatted base price string.
  String get formattedPrice {
    if (basePriceCents == 0) return 'Free';
    final dollars = basePriceCents / 100;
    return '\$${dollars.toStringAsFixed(dollars.truncateToDouble() == dollars ? 0 : 2)}';
  }

  /// Price range string if variants have different prices.
  String get priceRange {
    if (variants.isEmpty) return formattedPrice;
    final prices = variants.map((v) => v.priceCents).toSet().toList()..sort();
    if (prices.length == 1) {
      return '\$${(prices.first / 100).toStringAsFixed(2)}';
    }
    return '\$${(prices.first / 100).toStringAsFixed(2)} - \$${(prices.last / 100).toStringAsFixed(2)}';
  }

  /// Whether any variant is in stock.
  bool get inStock => variants.isEmpty || variants.any((v) => v.inStock);

  /// First image URL for thumbnails.
  String? get thumbnailUrl => imageUrls.isNotEmpty ? imageUrls.first : null;

  factory MerchProduct.fromJson(Map<String, dynamic> json) {
    final imageUrlsRaw = json['image_urls'];
    final List<String> urls = imageUrlsRaw is List
        ? imageUrlsRaw.cast<String>()
        : <String>[];

    final variantsRaw = json['merch_variants'] ?? json['variants'];
    final List<MerchVariant> variants = variantsRaw is List
        ? variantsRaw.map((v) => MerchVariant.fromJson(v as Map<String, dynamic>)).toList()
        : <MerchVariant>[];

    return MerchProduct(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      source: json['source'] as String,
      externalId: json['external_id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      imageUrls: urls,
      basePriceCents: json['base_price_cents'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      eventId: json['event_id'] as String?,
      fulfillmentType: FulfillmentType.fromString(json['fulfillment_type'] as String?),
      variants: variants,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'organizer_id': organizerId,
      'source': source,
      if (externalId != null) 'external_id': externalId,
      'title': title,
      'description': description,
      'image_urls': imageUrls,
      'base_price_cents': basePriceCents,
      'is_active': isActive,
      'event_id': eventId,
      'fulfillment_type': fulfillmentType.value,
    };
  }

  MerchProduct copyWith({
    String? id,
    String? organizerId,
    String? source,
    String? externalId,
    String? title,
    String? description,
    List<String>? imageUrls,
    int? basePriceCents,
    bool? isActive,
    String? eventId,
    bool clearEventId = false,
    FulfillmentType? fulfillmentType,
    List<MerchVariant>? variants,
    DateTime? createdAt,
  }) {
    return MerchProduct(
      id: id ?? this.id,
      organizerId: organizerId ?? this.organizerId,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrls: imageUrls ?? this.imageUrls,
      basePriceCents: basePriceCents ?? this.basePriceCents,
      isActive: isActive ?? this.isActive,
      eventId: clearEventId ? null : (eventId ?? this.eventId),
      fulfillmentType: fulfillmentType ?? this.fulfillmentType,
      variants: variants ?? this.variants,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MerchProduct && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
