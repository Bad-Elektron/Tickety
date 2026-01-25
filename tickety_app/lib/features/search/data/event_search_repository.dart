import '../../../core/services/services.dart';
import '../../events/data/event_mapper.dart';
import '../../events/models/event_model.dart';
import '../../events/models/event_tag.dart';

/// Repository for searching events.
///
/// This is structured to be easily extendable for database/API integration.
abstract class EventSearchRepository {
  /// Search events by query string.
  Future<List<EventModel>> search(String query);

  /// Get trending/popular events.
  Future<List<EventModel>> getTrending();

  /// Get recent searches (for suggestions).
  Future<List<String>> getRecentSearches();

  /// Save a search query to history.
  Future<void> saveSearch(String query);
}

/// Supabase implementation that searches real events from the database.
class SupabaseEventSearchRepository implements EventSearchRepository {
  static const _tableName = 'events';

  final _client = SupabaseService.instance.client;
  final List<String> _recentSearches = [];

  /// Escapes special characters for PostgreSQL ILIKE patterns.
  /// Prevents query injection via %, _, and \ characters.
  String _escapeSearchQuery(String query) {
    return query
        .replaceAll(r'\', r'\\') // Escape backslash first
        .replaceAll('%', r'\%') // Escape wildcard
        .replaceAll('_', r'\_'); // Escape single-char wildcard
  }

  @override
  Future<List<EventModel>> search(String query) async {
    if (query.isEmpty) {
      return [];
    }

    final lowerQuery = query.toLowerCase().trim();
    // Escape special chars to prevent ILIKE injection
    final escapedQuery = _escapeSearchQuery(lowerQuery);

    // Search across multiple fields using OR conditions with ilike
    // Supabase uses PostgreSQL's ilike for case-insensitive pattern matching
    final response = await _client
        .from(_tableName)
        .select()
        .isFilter('deleted_at', null)
        .or('title.ilike.%$escapedQuery%,'
            'subtitle.ilike.%$escapedQuery%,'
            'category.ilike.%$escapedQuery%,'
            'city.ilike.%$escapedQuery%,'
            'venue.ilike.%$escapedQuery%,'
            'description.ilike.%$escapedQuery%')
        .order('date', ascending: true)
        .limit(20);

    final events = (response as List<dynamic>)
        .map((json) => EventMapper.fromJson(json as Map<String, dynamic>))
        .toList();

    // Also check for tag matches in-memory (since tags are stored as array)
    // This handles the case where user searches for a tag label like "underground"
    if (events.isEmpty) {
      // Try searching by tags - get all upcoming events and filter by tags
      final allResponse = await _client
          .from(_tableName)
          .select()
          .isFilter('deleted_at', null)
          .gte('date', DateTime.now().toUtc().toIso8601String())
          .order('date', ascending: true)
          .limit(100);

      final allEvents = (allResponse as List<dynamic>)
          .map((json) => EventMapper.fromJson(json as Map<String, dynamic>))
          .toList();

      // Filter by tag match
      return allEvents.where((event) {
        for (final tagId in event.tags) {
          if (tagId.toLowerCase().contains(lowerQuery)) return true;
          final tag = PredefinedTags.all.where((t) => t.id == tagId).firstOrNull;
          if (tag != null && tag.label.toLowerCase().contains(lowerQuery)) {
            return true;
          }
        }
        return false;
      }).toList();
    }

    return events;
  }

  @override
  Future<List<EventModel>> getTrending() async {
    // Get upcoming events, ordered by date (nearest first)
    // In production, you might rank by ticket sales or views
    final response = await _client
        .from(_tableName)
        .select()
        .isFilter('deleted_at', null)
        .gte('date', DateTime.now().toUtc().toIso8601String())
        .order('date', ascending: true)
        .limit(6);

    return (response as List<dynamic>)
        .map((json) => EventMapper.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<String>> getRecentSearches() async {
    // For now, keep recent searches in memory
    // In production, you might store these in local storage or a user_searches table
    return _recentSearches.take(5).toList();
  }

  @override
  Future<void> saveSearch(String query) async {
    if (query.isNotEmpty && !_recentSearches.contains(query)) {
      _recentSearches.insert(0, query);
      if (_recentSearches.length > 10) {
        _recentSearches.removeLast();
      }
    }
  }
}

/// In-memory implementation with placeholder data.
/// Kept for testing and fallback purposes.
class LocalEventSearchRepository implements EventSearchRepository {
  final List<String> _recentSearches = [];

  // Placeholder events pool for search
  static final List<EventModel> _allEvents = [
    EventModel(
      id: 'search_001',
      title: 'Summer Music Festival',
      subtitle: 'Three days of incredible live performances',
      description: 'Join us for the biggest music festival of the summer.',
      date: DateTime.now().add(const Duration(days: 14)),
      location: 'Central Park, New York',
      category: 'Music',
      priceInCents: 7500,
      noiseSeed: 42,
    ),
    EventModel(
      id: 'search_002',
      title: 'Tech Conference 2025',
      subtitle: 'The future of technology is here',
      description: 'Learn about the latest innovations in AI and more.',
      date: DateTime.now().add(const Duration(days: 30)),
      location: 'Convention Center, San Francisco',
      category: 'Technology',
      priceInCents: 29900,
      noiseSeed: 108,
    ),
    EventModel(
      id: 'search_003',
      title: 'Food & Wine Expo',
      subtitle: 'A culinary journey around the world',
      description: 'Sample dishes from renowned chefs.',
      date: DateTime.now().add(const Duration(days: 7)),
      location: 'Grand Hall, Chicago',
      category: 'Food & Drink',
      priceInCents: 4500,
      noiseSeed: 256,
    ),
    EventModel(
      id: 'search_004',
      title: 'Art Gallery Opening',
      subtitle: 'Contemporary masters exhibition',
      description: 'Be the first to see this exclusive collection.',
      date: DateTime.now().add(const Duration(days: 3)),
      location: 'Modern Art Museum, Los Angeles',
      category: 'Art',
      priceInCents: 0,
      noiseSeed: 777,
    ),
    EventModel(
      id: 'search_005',
      title: 'Marathon 2025',
      subtitle: 'Run for a cause, run for yourself',
      description: 'Join thousands of runners in this charity marathon.',
      date: DateTime.now().add(const Duration(days: 45)),
      location: 'Downtown, Boston',
      category: 'Sports',
      priceInCents: 5000,
      noiseSeed: 999,
    ),
    EventModel(
      id: 'search_006',
      title: 'Jazz Night Live',
      subtitle: 'Smooth sounds under the stars',
      description: 'An evening of classic and modern jazz.',
      date: DateTime.now().add(const Duration(days: 10)),
      location: 'Blue Note Club, NYC',
      category: 'Music',
      priceInCents: 3500,
      noiseSeed: 123,
    ),
    EventModel(
      id: 'search_007',
      title: 'Startup Pitch Night',
      subtitle: 'Watch tomorrow\'s unicorns today',
      description: 'Entrepreneurs pitch their ideas to investors.',
      date: DateTime.now().add(const Duration(days: 5)),
      location: 'Innovation Hub, Austin',
      category: 'Business',
      priceInCents: 0,
      noiseSeed: 456,
    ),
    EventModel(
      id: 'search_008',
      title: 'Comedy Show',
      subtitle: 'Laugh until it hurts',
      description: 'Top comedians perform live on stage.',
      date: DateTime.now().add(const Duration(days: 8)),
      location: 'Laugh Factory, LA',
      category: 'Entertainment',
      priceInCents: 2500,
      noiseSeed: 789,
    ),
  ];

  @override
  Future<List<EventModel>> search(String query) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    if (query.isEmpty) {
      return [];
    }

    final lowerQuery = query.toLowerCase();
    return _allEvents.where((event) {
      // Match title, subtitle, category, or location
      if (event.title.toLowerCase().contains(lowerQuery) ||
          event.subtitle.toLowerCase().contains(lowerQuery) ||
          (event.category?.toLowerCase().contains(lowerQuery) ?? false) ||
          (event.location?.toLowerCase().contains(lowerQuery) ?? false)) {
        return true;
      }

      // Match tags by ID or label
      for (final tagId in event.tags) {
        // Match tag ID directly
        if (tagId.toLowerCase().contains(lowerQuery)) return true;

        // Match tag label from PredefinedTags
        final tag =
            PredefinedTags.all.where((t) => t.id == tagId).firstOrNull;
        if (tag != null && tag.label.toLowerCase().contains(lowerQuery)) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  @override
  Future<List<EventModel>> getTrending() async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Return first 4 as "trending"
    return _allEvents.take(4).toList();
  }

  @override
  Future<List<String>> getRecentSearches() async {
    return _recentSearches.take(5).toList();
  }

  @override
  Future<void> saveSearch(String query) async {
    if (query.isNotEmpty && !_recentSearches.contains(query)) {
      _recentSearches.insert(0, query);
      if (_recentSearches.length > 10) {
        _recentSearches.removeLast();
      }
    }
  }
}
