import '../../../core/models/models.dart';
import '../models/event_model.dart';
import '../models/ticket_availability.dart';

/// Date filter options for my events query.
enum MyEventsDateFilter {
  /// Upcoming events + events ended within past week.
  recent,
  /// Only upcoming events.
  upcoming,
  /// All events regardless of date.
  all,
  /// Only past events.
  past,
}

/// Abstract repository interface for event data operations.
///
/// Defines the contract for fetching and managing events.
/// Implementations can use different data sources (Supabase, mock, etc).
abstract class EventRepository {
  /// Fetches upcoming events with pagination.
  ///
  /// [category] - Filter by event category.
  /// [city] - Filter by city name.
  /// [page] - Page number (0-indexed).
  /// [pageSize] - Number of items per page.
  Future<PaginatedResult<EventModel>> getUpcomingEvents({
    String? category,
    String? city,
    int page = 0,
    int pageSize = 20,
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

  /// Fetches events created by the current user (paginated).
  ///
  /// [dateFilter] - Filter by date range (recent, upcoming, all, past).
  /// [searchQuery] - Search by event title (case-insensitive).
  /// [page] - Page number (0-indexed).
  /// [pageSize] - Number of items per page.
  ///
  /// Results are sorted: upcoming events first (soonest first),
  /// then past events (most recent first).
  Future<PaginatedResult<EventModel>> getMyEvents({
    MyEventsDateFilter dateFilter = MyEventsDateFilter.recent,
    String? searchQuery,
    int page = 0,
    int pageSize = 20,
  });

  /// Gets ticket availability for an event using SQL aggregation.
  ///
  /// Returns counts without fetching individual ticket records.
  Future<TicketAvailability> getTicketAvailability(String eventId);
}
