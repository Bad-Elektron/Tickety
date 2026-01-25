import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/staff/models/ticket.dart';

void main() {
  group('Ticket', () {
    late Ticket ticket;
    late Map<String, dynamic> validJson;

    setUp(() {
      validJson = {
        'id': 'tkt_001',
        'event_id': 'evt_001',
        'ticket_number': 'TKT-123456-7890',
        'owner_email': 'test@example.com',
        'owner_name': 'John Doe',
        'owner_wallet_address': '0x1234567890',
        'price_paid_cents': 5000,
        'currency': 'USD',
        'sold_by': 'user_001',
        'sold_at': '2025-01-15T10:00:00Z',
        'checked_in_at': null,
        'checked_in_by': null,
        'status': 'valid',
        'created_at': '2025-01-15T10:00:00Z',
      };

      ticket = Ticket.fromJson(validJson);
    });

    test('fromJson creates valid ticket', () {
      expect(ticket.id, 'tkt_001');
      expect(ticket.eventId, 'evt_001');
      expect(ticket.ticketNumber, 'TKT-123456-7890');
      expect(ticket.ownerEmail, 'test@example.com');
      expect(ticket.ownerName, 'John Doe');
      expect(ticket.pricePaidCents, 5000);
      expect(ticket.status, TicketStatus.valid);
    });

    test('formattedPrice returns formatted price', () {
      expect(ticket.formattedPrice, '\$50.0');
    });

    test('formattedPrice handles zero price', () {
      final freeTicket = Ticket.fromJson({
        ...validJson,
        'price_paid_cents': 0,
      });
      expect(freeTicket.formattedPrice, '\$0.0');
    });

    test('isValid returns true for valid status', () {
      expect(ticket.isValid, isTrue);
      expect(ticket.isUsed, isFalse);
      expect(ticket.status, isNot(TicketStatus.cancelled));
    });

    test('isUsed returns true for used status', () {
      final usedTicket = Ticket.fromJson({
        ...validJson,
        'status': 'used',
        'checked_in_at': '2025-01-15T12:00:00Z',
        'checked_in_by': 'usher_001',
      });
      expect(usedTicket.isUsed, isTrue);
      expect(usedTicket.isValid, isFalse);
      expect(usedTicket.checkedInAt, isNotNull);
    });

    test('cancelled status is detected correctly', () {
      final cancelledTicket = Ticket.fromJson({
        ...validJson,
        'status': 'cancelled',
      });
      expect(cancelledTicket.status, TicketStatus.cancelled);
      expect(cancelledTicket.isValid, isFalse);
    });

    test('eventData is populated from join', () {
      final ticketWithEvent = Ticket.fromJson({
        ...validJson,
        'events': {
          'id': 'evt_001',
          'title': 'Test Event',
          'venue': 'Test Venue',
        },
      });
      expect(ticketWithEvent.eventData, isNotNull);
      expect(ticketWithEvent.eventData!['title'], 'Test Event');
    });

    test('handles null optional fields', () {
      final minimalJson = {
        'id': 'tkt_002',
        'event_id': 'evt_001',
        'ticket_number': 'TKT-000000-0000',
        'price_paid_cents': 0,
        'currency': 'USD',
        'sold_at': '2025-01-15T10:00:00Z',
        'status': 'valid',
        'created_at': '2025-01-15T10:00:00Z',
      };

      final minimalTicket = Ticket.fromJson(minimalJson);
      expect(minimalTicket.ownerEmail, isNull);
      expect(minimalTicket.ownerName, isNull);
      expect(minimalTicket.ownerWalletAddress, isNull);
      expect(minimalTicket.soldBy, isNull);
      expect(minimalTicket.checkedInAt, isNull);
    });
  });

  group('TicketStatus', () {
    test('fromString parses valid status', () {
      expect(TicketStatus.fromString('valid'), TicketStatus.valid);
      expect(TicketStatus.fromString('used'), TicketStatus.used);
      expect(TicketStatus.fromString('cancelled'), TicketStatus.cancelled);
      expect(TicketStatus.fromString('refunded'), TicketStatus.refunded);
    });

    test('fromString defaults to valid for unknown status', () {
      expect(TicketStatus.fromString('unknown'), TicketStatus.valid);
      expect(TicketStatus.fromString(null), TicketStatus.valid);
    });

    test('value returns correct string', () {
      expect(TicketStatus.valid.value, 'valid');
      expect(TicketStatus.used.value, 'used');
      expect(TicketStatus.cancelled.value, 'cancelled');
      expect(TicketStatus.refunded.value, 'refunded');
    });
  });
}
