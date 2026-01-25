import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/events/widgets/ticket_info_card.dart';
import 'package:tickety/features/staff/models/ticket.dart';

void main() {
  group('CheckInValidationStatus', () {
    test('has correct label for each status', () {
      expect(CheckInValidationStatus.valid.label, 'Valid Ticket');
      expect(CheckInValidationStatus.alreadyUsed.label, 'Already Checked In');
      expect(CheckInValidationStatus.cancelled.label, 'Ticket Cancelled');
      expect(CheckInValidationStatus.refunded.label, 'Ticket Refunded');
      expect(CheckInValidationStatus.wrongEvent.label, 'Wrong Event');
      expect(CheckInValidationStatus.notFound.label, 'Ticket Not Found');
    });

    test('has correct icon for each status', () {
      expect(CheckInValidationStatus.valid.icon, Icons.check_circle);
      expect(CheckInValidationStatus.alreadyUsed.icon, Icons.cancel);
      expect(CheckInValidationStatus.cancelled.icon, Icons.block);
      expect(CheckInValidationStatus.refunded.icon, Icons.undo);
      expect(CheckInValidationStatus.wrongEvent.icon, Icons.event_note);
      expect(CheckInValidationStatus.notFound.icon, Icons.error);
    });

    test('has correct color for each status', () {
      // Valid is green
      expect(CheckInValidationStatus.valid.color, const Color(0xFF4CAF50));
      // Already used is red
      expect(CheckInValidationStatus.alreadyUsed.color, const Color(0xFFF44336));
      // Cancelled is red
      expect(CheckInValidationStatus.cancelled.color, const Color(0xFFF44336));
      // Refunded is orange
      expect(CheckInValidationStatus.refunded.color, const Color(0xFFFF9800));
      // Wrong event is orange
      expect(CheckInValidationStatus.wrongEvent.color, const Color(0xFFFF9800));
      // Not found is red
      expect(CheckInValidationStatus.notFound.color, const Color(0xFFF44336));
    });

    group('fromTicket', () {
      test('returns valid for valid ticket', () {
        final ticket = _createTicket(status: TicketStatus.valid);
        expect(
          CheckInValidationStatus.fromTicket(ticket),
          CheckInValidationStatus.valid,
        );
      });

      test('returns alreadyUsed for used ticket', () {
        final ticket = _createTicket(status: TicketStatus.used);
        expect(
          CheckInValidationStatus.fromTicket(ticket),
          CheckInValidationStatus.alreadyUsed,
        );
      });

      test('returns cancelled for cancelled ticket', () {
        final ticket = _createTicket(status: TicketStatus.cancelled);
        expect(
          CheckInValidationStatus.fromTicket(ticket),
          CheckInValidationStatus.cancelled,
        );
      });

      test('returns refunded for refunded ticket', () {
        final ticket = _createTicket(status: TicketStatus.refunded);
        expect(
          CheckInValidationStatus.fromTicket(ticket),
          CheckInValidationStatus.refunded,
        );
      });
    });
  });
}

Ticket _createTicket({TicketStatus status = TicketStatus.valid}) {
  return Ticket.fromJson({
    'id': 'tkt_001',
    'event_id': 'evt_001',
    'ticket_number': 'TKT-123456-7890',
    'owner_email': 'test@example.com',
    'owner_name': 'John Doe',
    'price_paid_cents': 5000,
    'currency': 'USD',
    'sold_at': '2025-01-15T10:00:00Z',
    'status': status.value,
    'created_at': '2025-01-15T10:00:00Z',
    if (status == TicketStatus.used) ...{
      'checked_in_at': '2025-01-15T12:00:00Z',
      'checked_in_by': 'usher_001',
    },
  });
}
