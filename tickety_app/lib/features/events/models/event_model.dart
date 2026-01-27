import 'package:flutter/material.dart';

import '../../../core/graphics/graphics.dart';
import 'event_category.dart';
import 'event_tag.dart';

/// Represents an event that can be displayed in the application.
///
/// This model is designed to be backend-agnostic. In a real application,
/// you would create this from API responses using a factory constructor
/// or a separate mapper class.
@immutable
class EventModel {
  /// Unique identifier for the event.
  final String id;

  /// Display title of the event.
  final String title;

  /// Short description or tagline for the event.
  final String subtitle;

  /// Full description of the event.
  final String? description;

  /// When the event takes place.
  final DateTime date;

  /// Location where the event is held (deprecated, use venue/city/country).
  final String? location;

  /// Venue name where the event is held.
  final String? venue;

  /// City where the event takes place.
  final String? city;

  /// Country where the event takes place.
  final String? country;

  /// URL to the event's cover image.
  /// If null, a noise background will be generated using [noiseSeed].
  final String? imageUrl;

  /// Seed for generating consistent noise backgrounds.
  /// Each event should have a unique seed for visual variety.
  final int noiseSeed;

  /// Optional custom noise configuration.
  /// If null, a preset will be selected based on the event properties.
  final NoiseConfig? customNoiseConfig;

  /// Category or type of the event (e.g., "Concert", "Conference").
  final String? category;

  /// Tags applied to this event (tag IDs).
  final List<String> tags;

  /// Price in the smallest currency unit (e.g., cents).
  /// Null means free or price not available.
  final int? priceInCents;

  /// Currency code (e.g., "USD", "EUR").
  final String currency;

  /// Whether the location should be hidden until ticket purchase.
  /// When true, venue/city/country are only shown to ticket holders.
  final bool hideLocation;

  const EventModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.noiseSeed,
    this.description,
    this.location,
    this.venue,
    this.city,
    this.country,
    this.imageUrl,
    this.customNoiseConfig,
    this.category,
    this.tags = const [],
    this.priceInCents,
    this.currency = 'USD',
    this.hideLocation = false,
  });

  /// Whether this event has a real image or should use a noise background.
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// Whether the event is free.
  bool get isFree => priceInCents == null || priceInCents == 0;

  /// Combines venue and city for display purposes.
  /// Falls back to [location] if venue/city are not set.
  /// Note: This returns the raw location regardless of [hideLocation].
  /// Use [getDisplayLocation] to respect the hide setting.
  String? get displayLocation {
    if (venue != null && city != null) {
      return '$venue, $city';
    }
    if (venue != null) return venue;
    if (city != null) return city;
    return location;
  }

  /// Returns the location for display, respecting [hideLocation] setting.
  /// If [hideLocation] is true and [hasTicket] is false, returns a placeholder.
  String? getDisplayLocation({required bool hasTicket}) {
    if (hideLocation && !hasTicket) {
      return 'Location revealed after purchase';
    }
    return displayLocation;
  }

  /// Returns the parsed [EventCategory] for this event.
  /// Returns null if the category string doesn't match any known category.
  EventCategory? get eventCategory => EventCategory.fromString(category);

  /// Returns the [EventTag] objects for this event's tags.
  List<EventTag> get eventTags {
    return tags
        .map((tagId) =>
            PredefinedTags.all.where((t) => t.id == tagId).firstOrNull)
        .whereType<EventTag>()
        .toList();
  }

  /// Returns true if this event has the specified tag.
  bool hasTag(String tagId) => tags.contains(tagId);

  /// Formatted price string.
  String get formattedPrice {
    if (isFree) return 'Free';
    final dollars = priceInCents! / 100;
    return '\$$dollars';
  }

  /// Gets the noise configuration for this event.
  ///
  /// Returns [customNoiseConfig] if set, otherwise generates
  /// a preset configuration based on the event's [noiseSeed].
  NoiseConfig getNoiseConfig() {
    if (customNoiseConfig != null) return customNoiseConfig!;

    // Rotate through presets based on seed for variety
    final presetIndex = noiseSeed % 5;
    return switch (presetIndex) {
      0 => NoisePresets.vibrantEvents(noiseSeed),
      1 => NoisePresets.sunset(noiseSeed),
      2 => NoisePresets.ocean(noiseSeed),
      3 => NoisePresets.subtle(noiseSeed),
      _ => NoisePresets.darkMood(noiseSeed),
    };
  }

  /// Creates a copy with modified properties.
  EventModel copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? description,
    DateTime? date,
    String? location,
    String? venue,
    String? city,
    String? country,
    String? imageUrl,
    int? noiseSeed,
    NoiseConfig? customNoiseConfig,
    String? category,
    List<String>? tags,
    int? priceInCents,
    String? currency,
    bool? hideLocation,
  }) {
    return EventModel(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      description: description ?? this.description,
      date: date ?? this.date,
      location: location ?? this.location,
      venue: venue ?? this.venue,
      city: city ?? this.city,
      country: country ?? this.country,
      imageUrl: imageUrl ?? this.imageUrl,
      noiseSeed: noiseSeed ?? this.noiseSeed,
      customNoiseConfig: customNoiseConfig ?? this.customNoiseConfig,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      priceInCents: priceInCents ?? this.priceInCents,
      currency: currency ?? this.currency,
      hideLocation: hideLocation ?? this.hideLocation,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EventModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Provides placeholder events for development and testing.
///
/// In production, these would come from an API or local database.
abstract class PlaceholderEvents {
  /// Featured events for the carousel (first 5 upcoming events).
  static List<EventModel> get featured => upcoming.take(5).toList();

  static final List<EventModel> upcoming = [
    EventModel(
      id: 'evt_001',
      title: 'Summer Music Festival',
      subtitle: 'Three days of incredible live performances',
      description:
          'Join us for the biggest music festival of the summer featuring '
          'top artists from around the world.',
      date: DateTime.now().add(const Duration(days: 14)),
      venue: 'Central Park',
      city: 'New York',
      country: 'USA',
      category: 'Music',
      priceInCents: 7500,
      noiseSeed: 42,
    ),
    EventModel(
      id: 'evt_002',
      title: 'Tech Conference 2025',
      subtitle: 'The future of technology is here',
      description:
          'Learn about the latest innovations in AI, blockchain, and more.',
      date: DateTime.now().add(const Duration(days: 30)),
      venue: 'Convention Center',
      city: 'San Francisco',
      country: 'USA',
      category: 'Technology',
      priceInCents: 29900,
      noiseSeed: 108,
    ),
    EventModel(
      id: 'evt_003',
      title: 'Food & Wine Expo',
      subtitle: 'A culinary journey around the world',
      description:
          'Sample dishes from renowned chefs and discover new wines.',
      date: DateTime.now().add(const Duration(days: 7)),
      venue: 'Grand Hall',
      city: 'Chicago',
      country: 'USA',
      category: 'Food & Drink',
      priceInCents: 4500,
      noiseSeed: 256,
    ),
    EventModel(
      id: 'evt_004',
      title: 'Art Gallery Opening',
      subtitle: 'Contemporary masters exhibition',
      description: 'Be the first to see this exclusive collection of works.',
      date: DateTime.now().add(const Duration(days: 3)),
      venue: 'Modern Art Museum',
      city: 'Los Angeles',
      country: 'USA',
      category: 'Art',
      priceInCents: 0,
      noiseSeed: 777,
    ),
    EventModel(
      id: 'evt_005',
      title: 'Marathon 2025',
      subtitle: 'Run for a cause, run for yourself',
      description: 'Join thousands of runners in this annual charity marathon.',
      date: DateTime.now().add(const Duration(days: 45)),
      venue: 'Downtown',
      city: 'Boston',
      country: 'USA',
      category: 'Sports',
      priceInCents: 5000,
      noiseSeed: 999,
    ),
    EventModel(
      id: 'evt_006',
      title: 'Broadway Musical Night',
      subtitle: 'A spectacular showcase of Broadway hits',
      description:
          'Experience the magic of Broadway with performances from acclaimed '
          'musicals.',
      date: DateTime.now().add(const Duration(days: 10)),
      venue: 'Lincoln Center',
      city: 'New York',
      country: 'USA',
      category: 'Theater',
      priceInCents: 12000,
      noiseSeed: 333,
    ),
    EventModel(
      id: 'evt_007',
      title: 'Startup Summit',
      subtitle: 'Connect with founders and investors',
      description:
          'Network with entrepreneurs and learn from successful founders.',
      date: DateTime.now().add(const Duration(days: 21)),
      venue: 'Tech Hub',
      city: 'San Francisco',
      country: 'USA',
      category: 'Business',
      priceInCents: 19900,
      noiseSeed: 444,
    ),
    EventModel(
      id: 'evt_008',
      title: 'Comedy Night Live',
      subtitle: 'Laugh until it hurts',
      description: 'Top comedians bring their best material for a night of fun.',
      date: DateTime.now().add(const Duration(days: 5)),
      venue: 'The Laugh Factory',
      city: 'Los Angeles',
      country: 'USA',
      category: 'Entertainment',
      priceInCents: 3500,
      noiseSeed: 555,
    ),
  ];
}
