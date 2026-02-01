import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tickety/main.dart';
import 'package:tickety/core/models/paginated_result.dart';
import 'package:tickety/core/providers/events_provider.dart';
import 'package:tickety/features/events/data/data.dart';
import 'package:tickety/features/events/models/event_model.dart';

class MockEventRepository extends Mock implements EventRepository {}

PaginatedResult<EventModel> _paginatedResult(List<EventModel> items) {
  return PaginatedResult(
    items: items,
    page: 0,
    pageSize: kEventsPageSize,
    hasMore: false,
  );
}

void main() {
  late MockEventRepository mockRepository;

  setUp(() {
    mockRepository = MockEventRepository();
  });

  testWidgets('App renders home screen', (WidgetTester tester) async {
    // Set up mock to return placeholder events
    when(() => mockRepository.getUpcomingEvents(
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).thenAnswer((_) async => _paginatedResult(PlaceholderEvents.upcoming));
    when(() => mockRepository.getFeaturedEvents(limit: any(named: 'limit')))
        .thenAnswer((_) async => PlaceholderEvents.featured);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Override the repository provider to use our mock
          eventRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: const TicketyApp(),
      ),
    );

    // Give time for async operations
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify the app renders with the discover header
    expect(find.text('Discover'), findsOneWidget);
  });

  testWidgets('App renders MaterialApp correctly', (WidgetTester tester) async {
    // Set up mock to return empty lists quickly
    when(() => mockRepository.getUpcomingEvents(
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).thenAnswer((_) async => _paginatedResult([]));
    when(() => mockRepository.getFeaturedEvents(limit: any(named: 'limit')))
        .thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: const TicketyApp(),
      ),
    );

    // Initial pump
    await tester.pump();

    // Verify the app renders (main scaffold)
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
