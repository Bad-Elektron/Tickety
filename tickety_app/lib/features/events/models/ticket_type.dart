import 'package:flutter/material.dart';

/// Represents a type of ticket available for an event.
///
/// Events can have multiple ticket types with different prices,
/// quantities, and perks (e.g., VIP, General Admission, Early Bird).
@immutable
class TicketType {
  /// Unique identifier for this ticket type.
  final String id;

  /// Event this ticket type belongs to.
  final String eventId;

  /// Display name (e.g., "VIP", "General Admission", "Early Bird").
  final String name;

  /// Optional description of what this ticket type includes.
  final String? description;

  /// Price in the smallest currency unit (e.g., cents).
  final int priceInCents;

  /// Currency code (e.g., "USD", "EUR").
  final String currency;

  /// Maximum number of tickets available for this type.
  /// Null means unlimited.
  final int? maxQuantity;

  /// Number of tickets already sold for this type.
  final int soldCount;

  /// Display order for sorting (lower numbers shown first).
  final int sortOrder;

  /// Whether this ticket type is currently available for sale.
  final bool isActive;

  /// When this ticket type was created.
  final DateTime createdAt;

  const TicketType({
    required this.id,
    required this.eventId,
    required this.name,
    required this.priceInCents,
    this.description,
    this.currency = 'USD',
    this.maxQuantity,
    this.soldCount = 0,
    this.sortOrder = 0,
    this.isActive = true,
    required this.createdAt,
  });

  /// Whether this ticket type has limited quantity.
  bool get hasLimit => maxQuantity != null;

  /// Number of tickets still available.
  /// Returns null if unlimited.
  int? get remainingQuantity {
    if (maxQuantity == null) return null;
    return maxQuantity! - soldCount;
  }

  /// Whether tickets of this type are still available.
  bool get isAvailable {
    if (!isActive) return false;
    if (maxQuantity == null) return true;
    return soldCount < maxQuantity!;
  }

  /// Whether this ticket type is sold out.
  bool get isSoldOut {
    if (maxQuantity == null) return false;
    return soldCount >= maxQuantity!;
  }

  /// Formatted price string.
  String get formattedPrice {
    if (priceInCents == 0) return 'Free';
    final dollars = priceInCents / 100;
    return '\$${dollars.toStringAsFixed(dollars.truncateToDouble() == dollars ? 0 : 2)}';
  }

  /// Availability text for display.
  String get availabilityText {
    if (!isActive) return 'Not available';
    if (isSoldOut) return 'Sold out';
    if (maxQuantity != null) {
      final remaining = remainingQuantity!;
      if (remaining <= 10) return '$remaining left';
    }
    return 'Available';
  }

  /// Creates from JSON (typically from Supabase).
  factory TicketType.fromJson(Map<String, dynamic> json) {
    return TicketType(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      priceInCents: json['price_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'USD',
      maxQuantity: json['max_quantity'] as int?,
      soldCount: json['sold_count'] as int? ?? 0,
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Converts to JSON for storage.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_id': eventId,
      'name': name,
      'description': description,
      'price_cents': priceInCents,
      'currency': currency,
      'max_quantity': maxQuantity,
      'sold_count': soldCount,
      'sort_order': sortOrder,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Creates a copy with modified properties.
  TicketType copyWith({
    String? id,
    String? eventId,
    String? name,
    String? description,
    int? priceInCents,
    String? currency,
    int? maxQuantity,
    int? soldCount,
    int? sortOrder,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return TicketType(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      name: name ?? this.name,
      description: description ?? this.description,
      priceInCents: priceInCents ?? this.priceInCents,
      currency: currency ?? this.currency,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      soldCount: soldCount ?? this.soldCount,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TicketType && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
