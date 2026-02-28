import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env_config.dart';

/// A prediction result from the Places Autocomplete API.
class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
}

/// Detailed place information from the Places Details API.
class PlaceDetails {
  final String placeId;
  final String formattedAddress;
  final String name;
  final double lat;
  final double lng;
  final String? city;
  final String? country;

  const PlaceDetails({
    required this.placeId,
    required this.formattedAddress,
    required this.name,
    required this.lat,
    required this.lng,
    this.city,
    this.country,
  });
}

/// Service for interacting with the Google Places API via HTTP.
class GooglePlacesService {
  static const _baseUrl = 'https://maps.googleapis.com/maps/api/place';

  final http.Client _client;

  GooglePlacesService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches autocomplete predictions for the given [input] string.
  Future<List<PlacePrediction>> getAutocompletePredictions(String input) async {
    if (input.trim().isEmpty) return [];

    final apiKey = EnvConfig.googlePlacesApiKey;
    final uri = Uri.parse(
      '$_baseUrl/autocomplete/json'
      '?input=${Uri.encodeComponent(input)}'
      '&types=establishment|geocode'
      '&key=$apiKey',
    );

    final response = await _client.get(uri);
    if (response.statusCode != 200) return [];

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final status = json['status'] as String?;
    if (status != 'OK' && status != 'ZERO_RESULTS') return [];

    final predictions = json['predictions'] as List<dynamic>? ?? [];
    return predictions.map((p) {
      final structured = p['structured_formatting'] as Map<String, dynamic>? ?? {};
      return PlacePrediction(
        placeId: p['place_id'] as String,
        description: p['description'] as String,
        mainText: structured['main_text'] as String? ?? p['description'] as String,
        secondaryText: structured['secondary_text'] as String? ?? '',
      );
    }).toList();
  }

  /// Fetches detailed place information for the given [placeId].
  ///
  /// Uses field masking to only request Basic tier fields (no extra cost).
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    final apiKey = EnvConfig.googlePlacesApiKey;
    final uri = Uri.parse(
      '$_baseUrl/details/json'
      '?place_id=$placeId'
      '&fields=place_id,formatted_address,name,geometry,address_components'
      '&key=$apiKey',
    );

    final response = await _client.get(uri);
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['status'] != 'OK') return null;

    final result = json['result'] as Map<String, dynamic>;
    final geometry = result['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;

    if (location == null) return null;

    // Extract city and country from address components
    String? city;
    String? country;
    final components = result['address_components'] as List<dynamic>? ?? [];
    for (final component in components) {
      final types = (component['types'] as List<dynamic>).cast<String>();
      if (types.contains('locality')) {
        city = component['long_name'] as String?;
      } else if (city == null && types.contains('administrative_area_level_1')) {
        // Fallback to admin area if no locality
        city = component['long_name'] as String?;
      }
      if (types.contains('country')) {
        country = component['long_name'] as String?;
      }
    }

    return PlaceDetails(
      placeId: placeId,
      formattedAddress: result['formatted_address'] as String? ?? '',
      name: result['name'] as String? ?? '',
      lat: (location['lat'] as num).toDouble(),
      lng: (location['lng'] as num).toDouble(),
      city: city,
      country: country,
    );
  }

  /// Disposes the HTTP client.
  void dispose() {
    _client.close();
  }
}
