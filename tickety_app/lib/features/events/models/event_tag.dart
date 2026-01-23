import 'package:flutter/material.dart';

/// Represents a tag that can be applied to an event.
@immutable
class EventTag {
  final String id;
  final String label;
  final Color? color;
  final IconData? icon;
  final bool isCustom;

  const EventTag({
    required this.id,
    required this.label,
    this.color,
    this.icon,
    this.isCustom = false,
  });

  /// Creates a custom user-defined tag.
  factory EventTag.custom(String label) {
    return EventTag(
      id: 'custom_${label.toLowerCase().replaceAll(' ', '_')}',
      label: label,
      isCustom: true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EventTag && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'isCustom': isCustom,
      };

  factory EventTag.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final label = json['label'] as String;
    final isCustom = json['isCustom'] as bool? ?? false;

    if (!isCustom) {
      // Try to find in predefined tags
      final predefined = PredefinedTags.all.where((t) => t.id == id);
      if (predefined.isNotEmpty) return predefined.first;
    }

    return EventTag(
      id: id,
      label: label,
      isCustom: isCustom,
    );
  }
}

/// Predefined tags for quick selection.
abstract class PredefinedTags {
  // Vibe tags
  static const underground = EventTag(
    id: 'underground',
    label: 'Underground',
    icon: Icons.subway,
    color: Color(0xFF6B7280),
  );

  static const hot = EventTag(
    id: 'hot',
    label: 'Hot',
    icon: Icons.local_fire_department,
    color: Color(0xFFEF4444),
  );

  static const exclusive = EventTag(
    id: 'exclusive',
    label: 'Exclusive',
    icon: Icons.diamond,
    color: Color(0xFF8B5CF6),
  );

  static const trending = EventTag(
    id: 'trending',
    label: 'Trending',
    icon: Icons.trending_up,
    color: Color(0xFF10B981),
  );

  static const newTag = EventTag(
    id: 'new',
    label: 'New',
    icon: Icons.new_releases,
    color: Color(0xFF3B82F6),
  );

  static const limited = EventTag(
    id: 'limited',
    label: 'Limited',
    icon: Icons.hourglass_bottom,
    color: Color(0xFFF59E0B),
  );

  // Category tags
  static const liveMusic = EventTag(
    id: 'live_music',
    label: 'Live Music',
    icon: Icons.music_note,
    color: Color(0xFFEC4899),
  );

  static const dj = EventTag(
    id: 'dj',
    label: 'DJ Set',
    icon: Icons.headphones,
    color: Color(0xFF6366F1),
  );

  static const outdoor = EventTag(
    id: 'outdoor',
    label: 'Outdoor',
    icon: Icons.park,
    color: Color(0xFF22C55E),
  );

  static const nightlife = EventTag(
    id: 'nightlife',
    label: 'Nightlife',
    icon: Icons.nightlife,
    color: Color(0xFF7C3AED),
  );

  static const familyFriendly = EventTag(
    id: 'family_friendly',
    label: 'Family Friendly',
    icon: Icons.family_restroom,
    color: Color(0xFF06B6D4),
  );

  static const food = EventTag(
    id: 'food',
    label: 'Food',
    icon: Icons.restaurant,
    color: Color(0xFFF97316),
  );

  static const drinks = EventTag(
    id: 'drinks',
    label: 'Drinks',
    icon: Icons.local_bar,
    color: Color(0xFFDB2777),
  );

  static const networking = EventTag(
    id: 'networking',
    label: 'Networking',
    icon: Icons.people,
    color: Color(0xFF0EA5E9),
  );

  static const workshop = EventTag(
    id: 'workshop',
    label: 'Workshop',
    icon: Icons.construction,
    color: Color(0xFF84CC16),
  );

  static const free = EventTag(
    id: 'free',
    label: 'Free Entry',
    icon: Icons.money_off,
    color: Color(0xFF14B8A6),
  );

  /// All predefined tags.
  static const List<EventTag> all = [
    // Vibe section
    hot,
    trending,
    exclusive,
    underground,
    newTag,
    limited,
    // Category section
    liveMusic,
    dj,
    nightlife,
    outdoor,
    food,
    drinks,
    networking,
    workshop,
    familyFriendly,
    free,
  ];

  /// Tags grouped by type for display.
  static const Map<String, List<EventTag>> grouped = {
    'Vibe': [hot, trending, exclusive, underground, newTag, limited],
    'Type': [liveMusic, dj, nightlife, outdoor, food, drinks, networking, workshop, familyFriendly, free],
  };
}
