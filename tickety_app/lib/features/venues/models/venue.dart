import 'package:flutter/foundation.dart';

import 'venue_layout.dart';

/// A venue with its seating/layout configuration.
@immutable
class Venue {
  final String id;
  final String organizerId;
  final String name;
  final int canvasWidth;
  final int canvasHeight;
  final VenueLayout layout;
  final int totalCapacity;
  final String? thumbnailUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Venue({
    required this.id,
    required this.organizerId,
    required this.name,
    this.canvasWidth = 1200,
    this.canvasHeight = 800,
    this.layout = const VenueLayout(),
    this.totalCapacity = 0,
    this.thumbnailUrl,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  Venue copyWith({
    String? id,
    String? organizerId,
    String? name,
    int? canvasWidth,
    int? canvasHeight,
    VenueLayout? layout,
    int? totalCapacity,
    String? thumbnailUrl,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Venue(
      id: id ?? this.id,
      organizerId: organizerId ?? this.organizerId,
      name: name ?? this.name,
      canvasWidth: canvasWidth ?? this.canvasWidth,
      canvasHeight: canvasHeight ?? this.canvasHeight,
      layout: layout ?? this.layout,
      totalCapacity: totalCapacity ?? this.totalCapacity,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Venue.fromJson(Map<String, dynamic> json) {
    final layoutJson = json['layout_data'];
    return Venue(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      name: json['name'] as String,
      canvasWidth: json['canvas_width'] as int? ?? 1200,
      canvasHeight: json['canvas_height'] as int? ?? 800,
      layout: layoutJson is Map<String, dynamic>
          ? VenueLayout.fromJson(layoutJson)
          : const VenueLayout(),
      totalCapacity: json['total_capacity'] as int? ?? 0,
      thumbnailUrl: json['thumbnail_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'canvas_width': canvasWidth,
      'canvas_height': canvasHeight,
      'layout_data': layout.toJson(),
      'total_capacity': layout.totalCapacity,
      'is_active': isActive,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Venue && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
