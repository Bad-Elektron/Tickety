import 'package:flutter/material.dart';

/// Standardized event categories for filtering and display.
enum EventCategory {
  music(label: 'Music', icon: Icons.music_note),
  sports(label: 'Sports', icon: Icons.sports_soccer),
  theater(label: 'Theater', icon: Icons.theater_comedy),
  technology(label: 'Technology', icon: Icons.computer),
  foodAndDrink(label: 'Food & Drink', icon: Icons.restaurant),
  art(label: 'Art', icon: Icons.palette),
  business(label: 'Business', icon: Icons.business_center),
  entertainment(label: 'Entertainment', icon: Icons.celebration);

  const EventCategory({
    required this.label,
    required this.icon,
  });

  /// Human-readable label for display.
  final String label;

  /// Icon representing this category.
  final IconData icon;

  /// Attempts to match a category string to an enum value.
  /// Returns null if no match is found.
  static EventCategory? fromString(String? categoryString) {
    if (categoryString == null) return null;

    final normalized = categoryString.toLowerCase().replaceAll(' ', '').replaceAll('&', 'and');

    for (final category in EventCategory.values) {
      final enumNormalized = category.label.toLowerCase().replaceAll(' ', '').replaceAll('&', 'and');
      if (enumNormalized == normalized) {
        return category;
      }
    }
    return null;
  }
}
