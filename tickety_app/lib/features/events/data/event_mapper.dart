import 'dart:ui';

import '../../../core/graphics/graphics.dart';
import '../models/event_model.dart';

/// Maps between JSON data and [EventModel] instances.
///
/// Keeps serialization logic separate from the model class,
/// maintaining clean architecture boundaries.
abstract class EventMapper {
  /// Creates an [EventModel] from a Supabase JSON response.
  static EventModel fromJson(Map<String, dynamic> json) {
    // Parse tags - support both new tags array and legacy category field
    final tagsJson = json['tags'];
    final List<String> tags = tagsJson is List
        ? tagsJson.cast<String>()
        : (json['category'] != null ? [json['category'] as String] : []);

    // Parse organizer data from joined profiles
    final organizer = json['organizer'] as Map<String, dynamic>?;
    final organizerVerificationStatus =
        organizer?['identity_verification_status'] as String?;

    return EventModel(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      description: json['description'] as String?,
      date: DateTime.parse(json['date'] as String),
      location: json['location'] as String?,
      venue: json['venue'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      imageUrl: json['image_url'] as String?,
      noiseSeed: json['noise_seed'] as int? ?? 0,
      customNoiseConfig: _parseNoiseConfig(json['custom_noise_config']),
      category: json['category'] as String?,
      tags: tags,
      priceInCents: json['price_in_cents'] as int?,
      currency: json['currency'] as String? ?? 'USD',
      hideLocation: json['hide_location'] as bool? ?? false,
      maxTickets: json['max_tickets'] as int?,
      cashSalesEnabled: json['cash_sales_enabled'] as bool? ?? false,
      organizerName: organizer?['display_name'] as String?,
      organizerHandle: organizer?['handle'] as String?,
      organizerVerified: organizerVerificationStatus == 'verified',
      status: json['status'] as String? ?? 'active',
      statusReason: json['status_reason'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      formattedAddress: json['formatted_address'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      inviteCode: json['invite_code'] as String?,
    );
  }

  /// Converts an [EventModel] to JSON for Supabase insert/update.
  static Map<String, dynamic> toJson(EventModel event) {
    return {
      'title': event.title,
      'subtitle': event.subtitle,
      'description': event.description,
      'date': event.date.toUtc().toIso8601String(),
      'location': event.location ?? event.displayLocation,
      'venue': event.venue,
      'city': event.city,
      'country': event.country,
      'image_url': event.imageUrl,
      'noise_seed': event.noiseSeed,
      'custom_noise_config': _serializeNoiseConfig(event.customNoiseConfig),
      // Store both tags array and category for backward compatibility
      'tags': event.tags,
      'category': event.tags.isNotEmpty ? event.tags.first : event.category,
      'price_in_cents': event.priceInCents,
      'currency': event.currency,
      'hide_location': event.hideLocation,
      'max_tickets': event.maxTickets,
      'cash_sales_enabled': event.cashSalesEnabled,
      // Only include is_private when true (column may not exist yet on older DBs)
      if (event.isPrivate) 'is_private': event.isPrivate,
      // Only include location coordinates when present (columns may not exist yet)
      if (event.latitude != null) 'latitude': event.latitude,
      if (event.longitude != null) 'longitude': event.longitude,
      if (event.formattedAddress != null) 'formatted_address': event.formattedAddress,
    };
  }

  /// Converts an [EventModel] to JSON including ID (for updates).
  static Map<String, dynamic> toJsonWithId(EventModel event) {
    return {
      'id': event.id,
      ...toJson(event),
    };
  }

  static NoiseConfig? _parseNoiseConfig(dynamic json) {
    if (json == null) return null;
    if (json is! Map<String, dynamic>) return null;

    try {
      final colorsJson = json['colors'] as List<dynamic>?;
      if (colorsJson == null || colorsJson.isEmpty) return null;

      return NoiseConfig(
        scale: (json['scale'] as num?)?.toDouble() ?? 0.01,
        octaves: json['octaves'] as int? ?? 4,
        persistence: (json['persistence'] as num?)?.toDouble() ?? 0.5,
        lacunarity: (json['lacunarity'] as num?)?.toDouble() ?? 2.0,
        colors: colorsJson.map((c) => Color(c as int)).toList(),
        seed: json['seed'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _serializeNoiseConfig(NoiseConfig? config) {
    if (config == null) return null;

    return {
      'scale': config.scale,
      'octaves': config.octaves,
      'persistence': config.persistence,
      'lacunarity': config.lacunarity,
      'colors': config.colors.map((c) => c.toARGB32()).toList(),
      'seed': config.seed,
    };
  }
}
