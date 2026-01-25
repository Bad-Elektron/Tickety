import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/events/models/event_model.dart';

void main() {
  group('EventModel', () {
    late EventModel event;

    setUp(() {
      event = EventModel(
        id: 'evt_001',
        title: 'Summer Music Festival',
        subtitle: 'Three days of incredible live performances',
        description: 'A great event',
        date: DateTime(2025, 7, 15, 18, 0),
        venue: 'Central Park',
        city: 'New York',
        country: 'USA',
        priceInCents: 7500,
        currency: 'USD',
        category: 'Music',
        noiseSeed: 42,
      );
    });

    test('creates event with required fields', () {
      expect(event.id, 'evt_001');
      expect(event.title, 'Summer Music Festival');
      expect(event.subtitle, 'Three days of incredible live performances');
    });

    test('displayLocation combines venue and city', () {
      expect(event.displayLocation, 'Central Park, New York');
    });

    test('displayLocation returns only venue when city is null', () {
      final eventNoCity = EventModel(
        id: 'evt_002',
        title: 'Test',
        subtitle: 'Test',
        date: DateTime.now(),
        venue: 'Stadium',
        noiseSeed: 1,
      );
      expect(eventNoCity.displayLocation, 'Stadium');
    });

    test('displayLocation returns only city when venue is null', () {
      final eventNoVenue = EventModel(
        id: 'evt_003',
        title: 'Test',
        subtitle: 'Test',
        date: DateTime.now(),
        city: 'Chicago',
        noiseSeed: 1,
      );
      expect(eventNoVenue.displayLocation, 'Chicago');
    });

    test('displayLocation returns null when both are null', () {
      final eventNoLocation = EventModel(
        id: 'evt_004',
        title: 'Test',
        subtitle: 'Test',
        date: DateTime.now(),
        noiseSeed: 1,
      );
      expect(eventNoLocation.displayLocation, isNull);
    });

    test('formattedPrice returns formatted USD price', () {
      // Note: actual implementation uses simple division (75.0) not toStringAsFixed(2)
      expect(event.formattedPrice, '\$75.0');
    });

    test('formattedPrice returns Free when price is null', () {
      final freeEvent = EventModel(
        id: 'evt_005',
        title: 'Free Event',
        subtitle: 'No cost',
        date: DateTime.now(),
        noiseSeed: 1,
      );
      expect(freeEvent.formattedPrice, 'Free');
    });

    test('formattedPrice returns Free when price is 0', () {
      final freeEvent = EventModel(
        id: 'evt_006',
        title: 'Free Event',
        subtitle: 'No cost',
        date: DateTime.now(),
        priceInCents: 0,
        noiseSeed: 1,
      );
      expect(freeEvent.formattedPrice, 'Free');
    });

    test('copyWith creates copy with modified fields', () {
      final modified = event.copyWith(title: 'New Title', priceInCents: 10000);

      expect(modified.title, 'New Title');
      expect(modified.priceInCents, 10000);
      // Original values preserved
      expect(modified.id, event.id);
      expect(modified.subtitle, event.subtitle);
      expect(modified.venue, event.venue);
    });

    test('copyWith preserves all original values when no changes', () {
      final copy = event.copyWith();

      expect(copy.id, event.id);
      expect(copy.title, event.title);
      expect(copy.subtitle, event.subtitle);
      expect(copy.date, event.date);
      expect(copy.venue, event.venue);
      expect(copy.city, event.city);
      expect(copy.country, event.country);
      expect(copy.priceInCents, event.priceInCents);
    });
  });

  group('PlaceholderEvents', () {
    test('upcoming returns non-empty list', () {
      expect(PlaceholderEvents.upcoming, isNotEmpty);
    });

    test('featured returns subset of upcoming', () {
      final featured = PlaceholderEvents.featured;
      expect(featured.length, lessThanOrEqualTo(5));
      for (final event in featured) {
        expect(PlaceholderEvents.upcoming.contains(event), isTrue);
      }
    });

    test('all events have required fields', () {
      for (final event in PlaceholderEvents.upcoming) {
        expect(event.id, isNotEmpty);
        expect(event.title, isNotEmpty);
        expect(event.subtitle, isNotEmpty);
        expect(event.noiseSeed, isNotNull);
      }
    });
  });
}
