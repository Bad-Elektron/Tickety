import '../models/event_model.dart';

/// Abstract repository interface for event data operations.
///
/// Defines the contract for fetching and managing events.
/// Implementations can use different data sources (Supabase, mock, etc).
abstract class EventRepository {
  /// Fetches all upcoming events, optionally filtered.
  ///
  /// [category] - Filter by event category.
  /// [city] - Filter by city name.
  /// [limit] - Maximum number of events to return.
  Future<List<EventModel>> getUpcomingEvents({
    String? category,
    String? city,
    int? limit,
  });

  /// Fetches a single event by its ID.
  ///
  /// Returns null if the event doesn't exist.
  Future<EventModel?> getEventById(String id);

  /// Fetches featured events for the home carousel.
  ///
  /// [limit] - Maximum number of events (defaults to 5).
  Future<List<EventModel>> getFeaturedEvents({int limit = 5});

  /// Creates a new event.
  ///
  /// Returns the created event with its server-assigned ID.
  /// Requires the user to be authenticated.
  Future<EventModel> createEvent(EventModel event);

  /// Updates an existing event.
  ///
  /// Returns the updated event.
  /// Requires the user to be the event organizer.
  Future<EventModel> updateEvent(EventModel event);

  /// Soft-deletes an event by setting deleted_at timestamp.
  ///
  /// Requires the user to be the event organizer.
  Future<void> deleteEvent(String id);

  /// Fetches events created by the current user.
  Future<List<EventModel>> getMyEvents();
}
