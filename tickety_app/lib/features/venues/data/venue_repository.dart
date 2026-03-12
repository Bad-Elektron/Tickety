import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/venue.dart';

/// Repository for venue CRUD operations.
class VenueRepository {
  final _client = Supabase.instance.client;

  /// Get all venues for the current user.
  Future<List<Venue>> getMyVenues() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final data = await _client
        .from('venues')
        .select()
        .eq('organizer_id', userId)
        .eq('is_active', true)
        .order('updated_at', ascending: false);

    return (data as List).map((json) => Venue.fromJson(json)).toList();
  }

  /// Get a single venue by ID.
  Future<Venue?> getVenue(String venueId) async {
    final data = await _client
        .from('venues')
        .select()
        .eq('id', venueId)
        .maybeSingle();

    if (data == null) return null;
    return Venue.fromJson(data);
  }

  /// Create a new venue.
  Future<Venue> createVenue({
    required String name,
    int canvasWidth = 1200,
    int canvasHeight = 800,
  }) async {
    final userId = _client.auth.currentUser!.id;

    final data = await _client
        .from('venues')
        .insert({
          'organizer_id': userId,
          'name': name,
          'canvas_width': canvasWidth,
          'canvas_height': canvasHeight,
        })
        .select()
        .single();

    return Venue.fromJson(data);
  }

  /// Update a venue's layout and metadata.
  Future<Venue> updateVenue(Venue venue) async {
    final data = await _client
        .from('venues')
        .update(venue.toJson())
        .eq('id', venue.id)
        .select()
        .single();

    return Venue.fromJson(data);
  }

  /// Soft-delete a venue.
  Future<void> deleteVenue(String venueId) async {
    await _client
        .from('venues')
        .update({'is_active': false})
        .eq('id', venueId);
  }

  // ────────────────────────────────────────────────────────────────
  // Seat availability & holds
  // ────────────────────────────────────────────────────────────────

  /// Returns the set of seat IDs that are unavailable (sold tickets + active holds)
  /// for a given event and section.
  Future<Set<String>> getUnavailableSeats(String eventId, String sectionId) async {
    // Sold tickets with this section/seat
    final soldData = await _client
        .from('tickets')
        .select('seat_id')
        .eq('event_id', eventId)
        .eq('venue_section_id', sectionId)
        .not('seat_id', 'is', null)
        .inFilter('status', ['valid', 'used']);

    // Active holds (not yet expired)
    final holdsData = await _client
        .from('seat_holds')
        .select('seat_id')
        .eq('event_id', eventId)
        .eq('venue_section_id', sectionId)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String());

    final ids = <String>{};
    for (final row in soldData as List) {
      final seatId = row['seat_id'] as String?;
      if (seatId != null) ids.add(seatId);
    }
    for (final row in holdsData as List) {
      final seatId = row['seat_id'] as String?;
      if (seatId != null) ids.add(seatId);
    }
    return ids;
  }

  /// Hold seats for checkout (10-minute TTL). Returns hold IDs.
  Future<List<String>> holdSeats(
    String eventId,
    List<({String sectionId, String seatId})> seats,
  ) async {
    final userId = _client.auth.currentUser!.id;
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String();

    final rows = seats.map((s) => {
      'event_id': eventId,
      'venue_section_id': s.sectionId,
      'seat_id': s.seatId,
      'user_id': userId,
      'expires_at': expiresAt,
    }).toList();

    final data = await _client
        .from('seat_holds')
        .upsert(rows, onConflict: 'event_id,venue_section_id,seat_id')
        .select('id');

    return (data as List).map((r) => r['id'] as String).toList();
  }

  /// Release seat holds by ID.
  Future<void> releaseHolds(List<String> holdIds) async {
    if (holdIds.isEmpty) return;
    await _client
        .from('seat_holds')
        .delete()
        .inFilter('id', holdIds);
  }

  /// Duplicate a venue with a new name.
  Future<Venue> duplicateVenue(String venueId, String newName) async {
    final original = await getVenue(venueId);
    if (original == null) throw Exception('Venue not found');

    final userId = _client.auth.currentUser!.id;

    final data = await _client
        .from('venues')
        .insert({
          'organizer_id': userId,
          'name': newName,
          'canvas_width': original.canvasWidth,
          'canvas_height': original.canvasHeight,
          'layout_data': original.layout.toJson(),
          'total_capacity': original.totalCapacity,
        })
        .select()
        .single();

    return Venue.fromJson(data);
  }
}
