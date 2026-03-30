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
  // ── Category tags (describe what the event IS) ──────────────

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

  static const art = EventTag(
    id: 'art',
    label: 'Art',
    icon: Icons.palette,
    color: Color(0xFFE11D48),
  );

  static const sports = EventTag(
    id: 'sports',
    label: 'Sports',
    icon: Icons.sports,
    color: Color(0xFF16A34A),
  );

  static const comedy = EventTag(
    id: 'comedy',
    label: 'Comedy',
    icon: Icons.sentiment_very_satisfied,
    color: Color(0xFFFBBF24),
  );

  static const theater = EventTag(
    id: 'theater',
    label: 'Theater',
    icon: Icons.theater_comedy,
    color: Color(0xFFD946EF),
  );

  static const wellness = EventTag(
    id: 'wellness',
    label: 'Wellness',
    icon: Icons.spa,
    color: Color(0xFF2DD4BF),
  );

  static const tech = EventTag(
    id: 'tech',
    label: 'Tech',
    icon: Icons.computer,
    color: Color(0xFF3B82F6),
  );

  // ── Curated vibe tags (marketing signal) ────────────────────

  static const exclusive = EventTag(
    id: 'exclusive',
    label: 'Exclusive',
    icon: Icons.diamond,
    color: Color(0xFF8B5CF6),
  );

  static const underground = EventTag(
    id: 'underground',
    label: 'Underground',
    icon: Icons.subway,
    color: Color(0xFF6B7280),
  );

  static const limitedEdition = EventTag(
    id: 'limited_edition',
    label: 'Limited Edition',
    icon: Icons.hourglass_bottom,
    color: Color(0xFFF59E0B),
  );

  static const immersive = EventTag(
    id: 'immersive',
    label: 'Immersive',
    icon: Icons.vrpano,
    color: Color(0xFF7C3AED),
  );

  static const chill = EventTag(
    id: 'chill',
    label: 'Chill',
    icon: Icons.waves,
    color: Color(0xFF06B6D4),
  );

  static const highEnergy = EventTag(
    id: 'high_energy',
    label: 'High Energy',
    icon: Icons.bolt,
    color: Color(0xFFEF4444),
  );

  /// All category tags.
  static const List<EventTag> categories = [
    liveMusic, dj, nightlife, outdoor, food, drinks,
    networking, workshop, familyFriendly, free,
    art, sports, comedy, theater, wellness, tech,
  ];

  /// All vibe tags.
  static const List<EventTag> vibes = [
    exclusive, underground, limitedEdition, immersive, chill, highEnergy,
  ];

  /// All predefined tags.
  static const List<EventTag> all = [
    ...categories,
    ...vibes,
  ];

  /// Tags grouped by type for display.
  static const Map<String, List<EventTag>> grouped = {
    'Category': categories,
    'Vibe': vibes,
  };
}

/// Auto-badges computed from real metrics, not user-selectable.
enum AutoBadge {
  hot(
    label: 'Hot',
    icon: Icons.local_fire_department,
    color: Color(0xFFEF4444),
  ),
  trending(
    label: 'Trending',
    icon: Icons.trending_up,
    color: Color(0xFF10B981),
  ),
  newEvent(
    label: 'New',
    icon: Icons.new_releases,
    color: Color(0xFF3B82F6),
  ),
  almostFull(
    label: 'Almost Full',
    icon: Icons.warning_amber,
    color: Color(0xFFF59E0B),
  ),
  sellingFast(
    label: 'Selling Fast',
    icon: Icons.bolt,
    color: Color(0xFFF97316),
  ),
  soldOut(
    label: 'Sold Out',
    icon: Icons.block,
    color: Color(0xFF6B7280),
  ),
  recurring(
    label: 'Recurring',
    icon: Icons.repeat,
    color: Color(0xFF8B5CF6),
  );

  const AutoBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Compute badges from EventModel fields alone (only "New" is reliable).
  static List<AutoBadge> forEvent({
    required DateTime? createdAt,
    bool isPartOfSeries = false,
  }) {
    final badges = <AutoBadge>[];
    if (isPartOfSeries) {
      badges.add(AutoBadge.recurring);
    }
    if (createdAt != null) {
      final daysSinceCreation = DateTime.now().difference(createdAt).inDays;
      if (daysSinceCreation <= 7) {
        badges.add(AutoBadge.newEvent);
      }
    }
    return badges;
  }

  /// Compute badges from ticket stats (for admin/detail screens with data).
  static List<AutoBadge> fromStats({
    required int? maxTickets,
    required int ticketsSold,
    required DateTime? createdAt,
  }) {
    final badges = <AutoBadge>[];

    if (createdAt != null) {
      final daysSinceCreation = DateTime.now().difference(createdAt).inDays;
      if (daysSinceCreation <= 7) {
        badges.add(AutoBadge.newEvent);
      }
    }

    if (maxTickets != null && maxTickets > 0) {
      final remaining = maxTickets - ticketsSold;
      final soldPct = ticketsSold / maxTickets;

      if (remaining <= 0) {
        badges.add(AutoBadge.soldOut);
      } else if (remaining < 10) {
        badges.add(AutoBadge.almostFull);
      }

      if (soldPct > 0.5 && remaining > 0) {
        badges.add(AutoBadge.hot);
      }
    }

    return badges;
  }
}
