import 'package:flutter/foundation.dart';

@immutable
class ExternalEvent {
  final String id;
  final String source;
  final String externalId;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime? endDate;
  final String? venueName;
  final String? venueAddress;
  final double? lat;
  final double? lng;
  final String? imageUrl;
  final String? category;
  final String? genre;
  final int? priceRangeMin;
  final int? priceRangeMax;
  final String ticketUrl;

  const ExternalEvent({
    required this.id,
    required this.source,
    required this.externalId,
    required this.title,
    this.description,
    required this.startDate,
    this.endDate,
    this.venueName,
    this.venueAddress,
    this.lat,
    this.lng,
    this.imageUrl,
    this.category,
    this.genre,
    this.priceRangeMin,
    this.priceRangeMax,
    required this.ticketUrl,
  });

  factory ExternalEvent.fromJson(Map<String, dynamic> json) {
    return ExternalEvent(
      id: json['id'] as String,
      source: json['source'] as String,
      externalId: json['external_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] != null ? DateTime.parse(json['end_date'] as String) : null,
      venueName: json['venue_name'] as String?,
      venueAddress: json['venue_address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      imageUrl: json['image_url'] as String?,
      category: json['category'] as String?,
      genre: json['genre'] as String?,
      priceRangeMin: json['price_range_min'] as int?,
      priceRangeMax: json['price_range_max'] as int?,
      ticketUrl: json['ticket_url'] as String,
    );
  }

  String get sourceLabel {
    switch (source) {
      case 'ticketmaster':
        return 'Ticketmaster';
      case 'seatgeek':
        return 'SeatGeek';
      case 'predicthq':
        return 'PredictHQ';
      default:
        return source;
    }
  }

  String get displayLocation {
    if (venueName != null && venueAddress != null) return '$venueName, $venueAddress';
    return venueName ?? venueAddress ?? '';
  }

  String get formattedPrice {
    if (priceRangeMin == null && priceRangeMax == null) return '';
    if (priceRangeMin != null && priceRangeMax != null && priceRangeMin != priceRangeMax) {
      return '\$${(priceRangeMin! / 100).toStringAsFixed(0)} - \$${(priceRangeMax! / 100).toStringAsFixed(0)}';
    }
    final price = priceRangeMin ?? priceRangeMax ?? 0;
    if (price == 0) return 'Free';
    return 'From \$${(price / 100).toStringAsFixed(0)}';
  }
}
