import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/events/data/event_mapper.dart';
import 'package:tickety/features/events/models/event_model.dart';

void main() {
  group('EventMapper', () {
    group('fromJson', () {
      test('parses complete JSON correctly', () {
        final json = {
          'id': 'evt_001',
          'title': 'Summer Festival',
          'subtitle': 'A great event',
          'description': 'Full description here',
          'date': '2025-07-15T18:00:00Z',
          'location': 'Downtown',
          'venue': 'Central Park',
          'city': 'New York',
          'country': 'USA',
          'image_url': 'https://example.com/image.jpg',
          'noise_seed': 42,
          'custom_noise_config': {'key': 'value'},
          'price_in_cents': 7500,
          'currency': 'USD',
          'category': 'Music',
          'organizer_id': 'user_001',
        };

        final event = EventMapper.fromJson(json);

        expect(event.id, 'evt_001');
        expect(event.title, 'Summer Festival');
        expect(event.subtitle, 'A great event');
        expect(event.description, 'Full description here');
        expect(event.venue, 'Central Park');
        expect(event.city, 'New York');
        expect(event.country, 'USA');
        expect(event.priceInCents, 7500);
        expect(event.currency, 'USD');
        expect(event.category, 'Music');
        expect(event.noiseSeed, 42);
      });

      test('handles null optional fields', () {
        final json = {
          'id': 'evt_002',
          'title': 'Minimal Event',
          'subtitle': 'No extras',
          'date': '2025-08-01T12:00:00Z',
          'noise_seed': 1,
        };

        final event = EventMapper.fromJson(json);

        expect(event.id, 'evt_002');
        expect(event.title, 'Minimal Event');
        expect(event.description, isNull);
        expect(event.venue, isNull);
        expect(event.city, isNull);
        expect(event.priceInCents, isNull);
        expect(event.imageUrl, isNull);
      });

      test('uses default noise seed when not provided', () {
        final json = {
          'id': 'evt_003',
          'title': 'No Seed',
          'subtitle': 'Test',
          'date': '2025-08-01T12:00:00Z',
        };

        final event = EventMapper.fromJson(json);
        expect(event.noiseSeed, 0);
      });

      test('parses date correctly', () {
        final json = {
          'id': 'evt_004',
          'title': 'Date Test',
          'subtitle': 'Test',
          'date': '2025-12-25T20:30:00Z',
          'noise_seed': 1,
        };

        final event = EventMapper.fromJson(json);

        expect(event.date.year, 2025);
        expect(event.date.month, 12);
        expect(event.date.day, 25);
      });
    });

    group('toJson', () {
      test('converts event to JSON correctly', () {
        final event = EventModel(
          id: 'evt_001',
          title: 'Test Event',
          subtitle: 'Subtitle',
          description: 'Description',
          date: DateTime.utc(2025, 7, 15, 18, 0),
          venue: 'Venue',
          city: 'City',
          country: 'Country',
          priceInCents: 5000,
          currency: 'USD',
          category: 'Music',
          noiseSeed: 42,
        );

        final json = EventMapper.toJson(event);

        expect(json['title'], 'Test Event');
        expect(json['subtitle'], 'Subtitle');
        expect(json['description'], 'Description');
        expect(json['venue'], 'Venue');
        expect(json['city'], 'City');
        expect(json['country'], 'Country');
        expect(json['price_in_cents'], 5000);
        expect(json['currency'], 'USD');
        expect(json['category'], 'Music');
        expect(json['noise_seed'], 42);
      });

      test('excludes id from JSON (server-generated)', () {
        final event = EventModel(
          id: 'evt_001',
          title: 'Test',
          subtitle: 'Test',
          date: DateTime.now(),
          noiseSeed: 1,
        );

        final json = EventMapper.toJson(event);

        expect(json.containsKey('id'), isFalse);
      });

      test('handles null optional fields', () {
        final event = EventModel(
          id: 'evt_002',
          title: 'Minimal',
          subtitle: 'Test',
          date: DateTime.now(),
          noiseSeed: 1,
        );

        final json = EventMapper.toJson(event);

        expect(json['description'], isNull);
        expect(json['venue'], isNull);
        expect(json['city'], isNull);
        expect(json['price_in_cents'], isNull);
      });
    });

    group('roundtrip', () {
      test('fromJson -> toJson -> fromJson preserves data', () {
        final originalJson = {
          'id': 'evt_001',
          'title': 'Roundtrip Test',
          'subtitle': 'Testing data preservation',
          'description': 'Full description',
          'date': '2025-07-15T18:00:00.000Z',
          'venue': 'Test Venue',
          'city': 'Test City',
          'country': 'Test Country',
          'price_in_cents': 9999,
          'currency': 'EUR',
          'category': 'Test',
          'noise_seed': 123,
        };

        final event = EventMapper.fromJson(originalJson);
        final json = EventMapper.toJson(event);

        // Add back the id for the second parse
        json['id'] = originalJson['id'];
        json['date'] = originalJson['date'];

        final roundtrippedEvent = EventMapper.fromJson(json);

        expect(roundtrippedEvent.title, event.title);
        expect(roundtrippedEvent.subtitle, event.subtitle);
        expect(roundtrippedEvent.description, event.description);
        expect(roundtrippedEvent.venue, event.venue);
        expect(roundtrippedEvent.city, event.city);
        expect(roundtrippedEvent.priceInCents, event.priceInCents);
        expect(roundtrippedEvent.noiseSeed, event.noiseSeed);
      });
    });
  });
}
