import 'package:flutter/material.dart';

/// Represents a ticket for an event.
@immutable
class TicketModel {
  final String id;
  final String eventId;
  final String eventTitle;
  final String holderName;
  final String holderEmail;
  final String ticketType;
  final DateTime purchaseDate;
  final DateTime eventDate;
  final bool isRedeemed;
  final DateTime? redeemedAt;
  final String? seatInfo;

  const TicketModel({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.holderName,
    required this.holderEmail,
    required this.ticketType,
    required this.purchaseDate,
    required this.eventDate,
    this.isRedeemed = false,
    this.redeemedAt,
    this.seatInfo,
  });

  /// Validation status for this ticket.
  TicketValidationStatus get validationStatus {
    if (isRedeemed) {
      return TicketValidationStatus.alreadyRedeemed;
    }
    if (eventDate.isBefore(DateTime.now().subtract(const Duration(hours: 6)))) {
      return TicketValidationStatus.eventPassed;
    }
    return TicketValidationStatus.valid;
  }
}

/// Validation status for scanned tickets.
enum TicketValidationStatus {
  valid(
    label: 'Valid Ticket',
    icon: Icons.check_circle,
    color: Color(0xFF4CAF50),
  ),
  alreadyRedeemed(
    label: 'Already Redeemed',
    icon: Icons.cancel,
    color: Color(0xFFF44336),
  ),
  eventPassed(
    label: 'Event Has Passed',
    icon: Icons.event_busy,
    color: Color(0xFFFF9800),
  ),
  invalidTicket(
    label: 'Invalid Ticket',
    icon: Icons.error,
    color: Color(0xFFF44336),
  ),
  wrongEvent(
    label: 'Wrong Event',
    icon: Icons.event_note,
    color: Color(0xFFFF9800),
  );

  const TicketValidationStatus({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

/// Placeholder ticket data for development.
abstract class PlaceholderTickets {
  static final List<TicketModel> forEvent = [
    TicketModel(
      id: 'tkt_001',
      eventId: 'my_evt_001',
      eventTitle: 'Birthday Bash 2025',
      holderName: 'John Smith',
      holderEmail: 'john.smith@email.com',
      ticketType: 'General Admission',
      purchaseDate: DateTime.now().subtract(const Duration(days: 5)),
      eventDate: DateTime.now().add(const Duration(days: 21)),
      seatInfo: null,
    ),
    TicketModel(
      id: 'tkt_002',
      eventId: 'my_evt_001',
      eventTitle: 'Birthday Bash 2025',
      holderName: 'Sarah Johnson',
      holderEmail: 'sarah.j@email.com',
      ticketType: 'VIP',
      purchaseDate: DateTime.now().subtract(const Duration(days: 3)),
      eventDate: DateTime.now().add(const Duration(days: 21)),
      seatInfo: 'Table 3',
    ),
    TicketModel(
      id: 'tkt_003',
      eventId: 'my_evt_001',
      eventTitle: 'Birthday Bash 2025',
      holderName: 'Mike Wilson',
      holderEmail: 'mike.w@email.com',
      ticketType: 'General Admission',
      purchaseDate: DateTime.now().subtract(const Duration(days: 1)),
      eventDate: DateTime.now().add(const Duration(days: 21)),
      isRedeemed: true,
      redeemedAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ];
}
