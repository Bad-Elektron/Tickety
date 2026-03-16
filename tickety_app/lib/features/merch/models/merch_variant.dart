import 'package:flutter/material.dart';

/// A variant of a merch product (e.g., size, color).
@immutable
class MerchVariant {
  final String id;
  final String productId;
  final String? externalId;
  final String name;
  final int priceCents;
  final int? inventoryCount;
  final String? sku;
  final int sortOrder;

  const MerchVariant({
    required this.id,
    required this.productId,
    this.externalId,
    required this.name,
    required this.priceCents,
    this.inventoryCount,
    this.sku,
    this.sortOrder = 0,
  });

  /// Whether this variant is in stock.
  bool get inStock => inventoryCount == null || inventoryCount! > 0;

  /// Formatted price.
  String get formattedPrice {
    final dollars = priceCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  factory MerchVariant.fromJson(Map<String, dynamic> json) {
    return MerchVariant(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      externalId: json['external_id'] as String?,
      name: json['name'] as String,
      priceCents: json['price_cents'] as int? ?? 0,
      inventoryCount: json['inventory_count'] as int?,
      sku: json['sku'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      if (externalId != null) 'external_id': externalId,
      'name': name,
      'price_cents': priceCents,
      'inventory_count': inventoryCount,
      if (sku != null) 'sku': sku,
      'sort_order': sortOrder,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MerchVariant && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
