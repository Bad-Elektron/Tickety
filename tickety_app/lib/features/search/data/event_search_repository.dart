import '../../events/models/event_model.dart';

/// Repository for searching events.
///
/// This is structured to be easily extendable for database/API integration.
/// Currently returns preloaded placeholder results.
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

/// In-memory implementation with placeholder data.
/// Replace with DatabaseEventSearchRepository or ApiEventSearchRepository later.
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
      return event.title.toLowerCase().contains(lowerQuery) ||
          event.subtitle.toLowerCase().contains(lowerQuery) ||
          (event.category?.toLowerCase().contains(lowerQuery) ?? false) ||
          (event.location?.toLowerCase().contains(lowerQuery) ?? false);
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
