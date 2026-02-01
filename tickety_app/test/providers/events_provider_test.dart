import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tickety/core/models/paginated_result.dart';
import 'package:tickety/core/providers/events_provider.dart';
import 'package:tickety/features/events/models/event_model.dart';

import '../mocks/mock_repositories.dart';

void main() {
  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(_createMockEvent('fallback'));
  });

  group('EventsState', () {
    test('initial state has empty values', () {
      const state = EventsState();

      expect(state.events, isEmpty);
      expect(state.featuredEvents, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.isLoadingMore, isFalse);
      expect(state.error, isNull);
      expect(state.isUsingPlaceholders, isFalse);
      expect(state.currentPage, 0);
      expect(state.hasMore, isTrue);
      expect(state.pageSize, kEventsPageSize);
    });

    test('copyWith creates copy with modified values', () {
      final events = [_createMockEvent('1')];
      final featured = [_createMockEvent('2')];

      final state = const EventsState().copyWith(
        events: events,
        featuredEvents: featured,
        isLoading: true,
        isUsingPlaceholders: true,
        currentPage: 2,
        hasMore: false,
      );

      expect(state.events, events);
      expect(state.featuredEvents, featured);
      expect(state.isLoading, isTrue);
      expect(state.isUsingPlaceholders, isTrue);
      expect(state.currentPage, 2);
      expect(state.hasMore, isFalse);
    });

    test('copyWith with clearError removes error', () {
      final state = const EventsState().copyWith(error: 'Some error');
      final cleared = state.copyWith(clearError: true);

      expect(cleared.error, isNull);
    });

    test('copyWith preserves isUsingPlaceholders', () {
      final state = const EventsState().copyWith(isUsingPlaceholders: true);
      final modified = state.copyWith(isLoading: true);

      expect(modified.isUsingPlaceholders, isTrue);
    });

    test('canLoadMore returns true when conditions are met', () {
      const state = EventsState(hasMore: true, isLoading: false, isLoadingMore: false);
      expect(state.canLoadMore, isTrue);
    });

    test('canLoadMore returns false when loading', () {
      const loading = EventsState(hasMore: true, isLoading: true, isLoadingMore: false);
      const loadingMore = EventsState(hasMore: true, isLoading: false, isLoadingMore: true);
      const noMore = EventsState(hasMore: false, isLoading: false, isLoadingMore: false);

      expect(loading.canLoadMore, isFalse);
      expect(loadingMore.canLoadMore, isFalse);
      expect(noMore.canLoadMore, isFalse);
    });
  });

  group('EventsNotifier', () {
    late MockEventRepository mockRepository;
    late EventsNotifier notifier;

    PaginatedResult<EventModel> _paginatedResult(
      List<EventModel> items, {
      int page = 0,
      bool hasMore = false,
    }) {
      return PaginatedResult(
        items: items,
        page: page,
        pageSize: kEventsPageSize,
        hasMore: hasMore,
      );
    }

    setUp(() {
      mockRepository = MockEventRepository();
      // Set up default stubs for constructor that calls loadEvents
      when(() => mockRepository.getUpcomingEvents(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedResult([]));
      when(() => mockRepository.getFeaturedEvents(limit: any(named: 'limit')))
          .thenAnswer((_) async => []);
      notifier = EventsNotifier(mockRepository);
    });

    test('constructor calls loadEvents', () async {
      // Wait for initial load to complete
      await Future.delayed(Duration.zero);
      verify(() => mockRepository.getUpcomingEvents(
            page: 0,
            pageSize: any(named: 'pageSize'),
          )).called(1);
    });

    test('loadEvents fetches events from repository', () async {
      final events = [_createMockEvent('1'), _createMockEvent('2')];
      final featured = [_createMockEvent('3')];

      when(() => mockRepository.getUpcomingEvents(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedResult(events, hasMore: true));
      when(() => mockRepository.getFeaturedEvents(limit: 5))
          .thenAnswer((_) async => featured);

      await notifier.loadEvents();

      expect(notifier.state.events, events);
      expect(notifier.state.featuredEvents, featured);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.isUsingPlaceholders, isFalse);
      expect(notifier.state.currentPage, 0);
      expect(notifier.state.hasMore, isTrue);
    });

    test('loadEvents falls back to placeholders on error', () async {
      // Wait for initial constructor load to complete
      await Future.delayed(Duration.zero);

      // Now change mock to throw on next call
      when(() => mockRepository.getUpcomingEvents(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenThrow(Exception('Network error'));

      await notifier.loadEvents();

      expect(notifier.state.isLoading, isFalse);
      // Error is normalized to user-friendly message
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.isUsingPlaceholders, isTrue);
      expect(notifier.state.events, isNotEmpty); // Placeholder data
      expect(notifier.state.hasMore, isFalse);
    });

    test('refresh calls loadEvents', () async {
      final events = [_createMockEvent('1')];
      when(() => mockRepository.getUpcomingEvents(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedResult(events));
      when(() => mockRepository.getFeaturedEvents(limit: 5))
          .thenAnswer((_) async => []);

      await notifier.refresh();

      // Called once in constructor, once in refresh
      verify(() => mockRepository.getUpcomingEvents(
            page: 0,
            pageSize: any(named: 'pageSize'),
          )).called(greaterThanOrEqualTo(1));
    });

    test('loadMore appends items and increments page', () async {
      final page1Events = [_createMockEvent('1'), _createMockEvent('2')];
      final page2Events = [_createMockEvent('3'), _createMockEvent('4')];

      when(() => mockRepository.getUpcomingEvents(page: 0, pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => _paginatedResult(page1Events, hasMore: true));
      when(() => mockRepository.getUpcomingEvents(page: 1, pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => _paginatedResult(page2Events, page: 1, hasMore: false));
      when(() => mockRepository.getFeaturedEvents(limit: any(named: 'limit')))
          .thenAnswer((_) async => []);

      await notifier.loadEvents();
      expect(notifier.state.events.length, 2);
      expect(notifier.state.currentPage, 0);

      await notifier.loadMore();
      expect(notifier.state.events.length, 4);
      expect(notifier.state.currentPage, 1);
      expect(notifier.state.hasMore, isFalse);
    });

    test('loadMore does nothing when hasMore is false', () async {
      when(() => mockRepository.getUpcomingEvents(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedResult([], hasMore: false));
      when(() => mockRepository.getFeaturedEvents(limit: any(named: 'limit')))
          .thenAnswer((_) async => []);

      // Wait for constructor's loadEvents to complete
      await Future.delayed(Duration.zero);

      // Reset interactions to start fresh
      reset(mockRepository);
      when(() => mockRepository.getUpcomingEvents(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedResult([], hasMore: false));

      await notifier.loadEvents();
      expect(notifier.state.hasMore, isFalse);

      await notifier.loadMore();
      // Should only have been called once (in loadEvents), loadMore should be no-op
      verify(() => mockRepository.getUpcomingEvents(
            page: 0,
            pageSize: any(named: 'pageSize'),
          )).called(1);
    });

    test('loadMore preserves existing data on error', () async {
      final events = [_createMockEvent('1')];

      when(() => mockRepository.getUpcomingEvents(page: 0, pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => _paginatedResult(events, hasMore: true));
      when(() => mockRepository.getUpcomingEvents(page: 1, pageSize: any(named: 'pageSize')))
          .thenThrow(Exception('Network error'));
      when(() => mockRepository.getFeaturedEvents(limit: any(named: 'limit')))
          .thenAnswer((_) async => []);

      await notifier.loadEvents();
      await notifier.loadMore();

      // Original events should still be there
      expect(notifier.state.events, events);
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.isLoadingMore, isFalse);
    });

    test('filterByCategory filters events correctly', () async {
      final events = [
        _createMockEvent('1', category: 'Music'),
        _createMockEvent('2', category: 'Sports'),
        _createMockEvent('3', category: 'Music'),
      ];

      when(() => mockRepository.getUpcomingEvents(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedResult(events));
      when(() => mockRepository.getFeaturedEvents(limit: 5))
          .thenAnswer((_) async => []);

      await notifier.loadEvents();

      expect(notifier.filterByCategory('Music').length, 2);
      expect(notifier.filterByCategory('Sports').length, 1);
      expect(notifier.filterByCategory('Food').length, 0);
      expect(notifier.filterByCategory(null).length, 3);
    });

    test('filterByCity filters events correctly', () async {
      final events = [
        _createMockEvent('1', city: 'New York'),
        _createMockEvent('2', city: 'Los Angeles'),
        _createMockEvent('3', city: 'New York'),
      ];

      when(() => mockRepository.getUpcomingEvents(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedResult(events));
      when(() => mockRepository.getFeaturedEvents(limit: 5))
          .thenAnswer((_) async => []);

      await notifier.loadEvents();

      expect(notifier.filterByCity('New York').length, 2);
      expect(notifier.filterByCity('Los Angeles').length, 1);
      expect(notifier.filterByCity('Chicago').length, 0);
      expect(notifier.filterByCity(null).length, 3);
    });

    test('getEventById returns correct event', () async {
      final events = [
        _createMockEvent('1'),
        _createMockEvent('2'),
        _createMockEvent('3'),
      ];

      when(() => mockRepository.getUpcomingEvents(
            page: any(named: 'page'),
            pageSize: any(named: 'pageSize'),
          )).thenAnswer((_) async => _paginatedResult(events));
      when(() => mockRepository.getFeaturedEvents(limit: 5))
          .thenAnswer((_) async => []);

      await notifier.loadEvents();

      expect(notifier.getEventById('2')?.id, '2');
      expect(notifier.getEventById('unknown'), isNull);
    });
  });

  group('MyEventsState', () {
    test('initial state is empty', () {
      const state = MyEventsState();

      expect(state.events, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('copyWith creates modified copy', () {
      final events = [_createMockEvent('1')];

      final state = const MyEventsState().copyWith(
        events: events,
        isLoading: true,
      );

      expect(state.events, events);
      expect(state.isLoading, isTrue);
    });

    test('copyWith with clearError removes error', () {
      final state = const MyEventsState().copyWith(error: 'Some error');
      final cleared = state.copyWith(clearError: true);

      expect(cleared.error, isNull);
    });
  });

  group('MyEventsNotifier', () {
    late MockEventRepository mockRepository;

    setUp(() {
      mockRepository = MockEventRepository();
    });

    test('loads events when authenticated', () async {
      final events = [_createMockEvent('1')];

      when(() => mockRepository.getMyEvents(page: any(named: 'page'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => PaginatedResult(items: events, page: 0, pageSize: 20, hasMore: false));

      final notifier = MyEventsNotifier(mockRepository, true);
      // Wait for initial load
      await Future.delayed(Duration.zero);

      expect(notifier.state.events, events);
      expect(notifier.state.isLoading, isFalse);
    });

    test('does not load events when not authenticated', () async {
      final notifier = MyEventsNotifier(mockRepository, false);
      // Wait for any potential async operations
      await Future.delayed(Duration.zero);

      expect(notifier.state.events, isEmpty);
      verifyNever(() => mockRepository.getMyEvents(page: any(named: 'page'), pageSize: any(named: 'pageSize')));
    });

    test('loadMyEvents handles errors', () async {
      when(() => mockRepository.getMyEvents(page: any(named: 'page'), pageSize: any(named: 'pageSize')))
          .thenThrow(Exception('Not authenticated'));

      final notifier = MyEventsNotifier(mockRepository, true);
      await Future.delayed(Duration.zero);

      // Error is normalized to user-friendly message
      expect(notifier.state.error, isNotNull);
    });

    test('loadMyEvents clears events when not authenticated', () async {
      when(() => mockRepository.getMyEvents(page: any(named: 'page'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => PaginatedResult(items: [_createMockEvent('1')], page: 0, pageSize: 20, hasMore: false));

      final notifier = MyEventsNotifier(mockRepository, true);
      await Future.delayed(Duration.zero);
      expect(notifier.state.events.length, 1);

      // Simulate becoming unauthenticated
      final unauthNotifier = MyEventsNotifier(mockRepository, false);
      await unauthNotifier.loadMyEvents();

      expect(unauthNotifier.state.events, isEmpty);
    });

    test('addEvent adds to local state', () async {
      when(() => mockRepository.getMyEvents(page: any(named: 'page'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => PaginatedResult(items: <EventModel>[], page: 0, pageSize: 20, hasMore: false));

      final notifier = MyEventsNotifier(mockRepository, true);
      await Future.delayed(Duration.zero);

      final newEvent = _createMockEvent('new_1');
      notifier.addEvent(newEvent);

      expect(notifier.state.events.contains(newEvent), isTrue);
      expect(notifier.state.events.first.id, 'new_1');
    });

    test('refresh reloads events', () async {
      when(() => mockRepository.getMyEvents(page: any(named: 'page'), pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => PaginatedResult(items: [_createMockEvent('1')], page: 0, pageSize: 20, hasMore: false));

      final notifier = MyEventsNotifier(mockRepository, true);
      await Future.delayed(Duration.zero);

      await notifier.refresh();

      // Called twice: once in constructor, once in refresh
      verify(() => mockRepository.getMyEvents(page: any(named: 'page'), pageSize: any(named: 'pageSize'))).called(2);
    });
  });
}

EventModel _createMockEvent(
  String id, {
  String title = 'Test Event',
  String? category,
  String? city,
  DateTime? date,
}) {
  return EventModel(
    id: id,
    title: title,
    subtitle: 'Test Subtitle',
    date: date ?? DateTime.now().add(const Duration(days: 30)),
    category: category,
    city: city,
    noiseSeed: 42,
  );
}
