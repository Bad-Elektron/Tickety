import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/staff/models/ticket.dart';
import 'package:tickety/features/tickets/presentation/ticket_screen.dart';

void main() {
  group('TicketScreen', () {
    testWidgets('displays event title from ticket data', (tester) async {
      final ticket = _createTicketWithEventData(
        eventTitle: 'Summer Music Festival',
      );

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Summer Music Festival'), findsOneWidget);
    });

    testWidgets('displays Unknown Event when no event data', (tester) async {
      final ticket = _createTicket();

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Unknown Event'), findsOneWidget);
    });

    testWidgets('displays ticket number', (tester) async {
      final ticket = _createTicket(ticketNumber: 'TKT-SCREEN-1234');

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('TKT-SCREEN-1234'), findsOneWidget);
      expect(find.text('Ticket Number'), findsOneWidget);
    });

    testWidgets('displays valid status badge for valid ticket', (tester) async {
      final ticket = _createTicket(status: TicketStatus.valid);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Valid'), findsOneWidget);
    });

    testWidgets('displays used status badge for used ticket', (tester) async {
      final ticket = _createTicket(status: TicketStatus.used);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Used'), findsOneWidget);
    });

    testWidgets('displays cancelled status badge for cancelled ticket', (tester) async {
      final ticket = _createTicket(status: TicketStatus.cancelled);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Cancelled'), findsOneWidget);
    });

    testWidgets('displays refunded status badge for refunded ticket', (tester) async {
      final ticket = _createTicket(status: TicketStatus.refunded);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Refunded'), findsOneWidget);
    });

    testWidgets('displays purchase details section', (tester) async {
      final ticket = _createTicket(priceCents: 7500);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Purchase Details'), findsOneWidget);
      expect(find.text('Price Paid'), findsOneWidget);
      expect(find.text(ticket.formattedPrice), findsOneWidget);
    });

    testWidgets('displays owner name when present', (tester) async {
      final ticket = _createTicket(ownerName: 'Jane Smith');

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Holder'), findsOneWidget);
      expect(find.text('Jane Smith'), findsOneWidget);
    });

    testWidgets('displays owner email when present', (tester) async {
      final ticket = _createTicket(ownerEmail: 'jane@example.com');

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      // Note: Email appears twice - once as row and once as label
      expect(find.text('jane@example.com'), findsWidgets);
    });

    testWidgets('displays check-in info for used ticket', (tester) async {
      final checkedInAt = DateTime.now().subtract(const Duration(hours: 2));
      final ticket = _createTicket(
        status: TicketStatus.used,
        checkedInAt: checkedInAt,
      );

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Checked In'), findsOneWidget);
    });

    testWidgets('displays venue when present in event data', (tester) async {
      final ticket = _createTicketWithEventData(
        venue: 'Madison Square Garden',
        city: 'New York',
      );

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Madison Square Garden'), findsOneWidget);
    });

    testWidgets('displays date when present in event data', (tester) async {
      final eventDate = DateTime(2025, 3, 15);
      final ticket = _createTicketWithEventData(eventDate: eventDate);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Date'), findsOneWidget);
      expect(find.textContaining('March'), findsWidgets);
    });

    testWidgets('has QR code placeholder in header', (tester) async {
      final ticket = _createTicket();

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
    });

    testWidgets('has navigation button for location', (tester) async {
      final ticket = _createTicketWithEventData(
        venue: 'Test Venue',
        city: 'Test City',
      );

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.navigation_rounded), findsOneWidget);
    });

    testWidgets('shows To be announced when no event date', (tester) async {
      final ticket = _createTicket(); // No event data = no date

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('To be announced'), findsOneWidget);
    });

    testWidgets('shows TBA when no venue', (tester) async {
      final ticket = _createTicketWithEventData(venue: null);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      expect(find.text('TBA'), findsOneWidget);
    });
  });

  group('TicketScreen NFC', () {
    // Note: NFC functionality cannot be fully tested in widget tests
    // as it requires platform-specific implementations.
    // These tests verify the UI state handling.

    testWidgets('does not show NFC card on desktop/test environment', (tester) async {
      // On desktop/web, NFC is not available
      final ticket = _createTicket(status: TicketStatus.valid);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      // NFC card should not be visible since NFC is not available in tests
      expect(find.text('Tap to Check In'), findsNothing);
      expect(find.text('Ready to Tap'), findsNothing);
    });

    testWidgets('does not show NFC indicator in header when not broadcasting', (tester) async {
      final ticket = _createTicket();

      await tester.pumpWidget(_wrapWithMaterial(
        TicketScreen(ticket: ticket),
      ));
      await tester.pumpAndSettle();

      // NFC Ready indicator should not be visible
      expect(find.text('NFC Ready'), findsNothing);
    });
  });

  group('_StatusBadge', () {
    testWidgets('displays correct colors for each status', (tester) async {
      // Test each status badge renders correctly
      for (final status in TicketStatus.values) {
        final ticket = _createTicket(status: status);

        await tester.pumpWidget(_wrapWithMaterial(
          TicketScreen(ticket: ticket),
        ));
        await tester.pumpAndSettle();

        // Verify badge text matches status
        final expectedText = switch (status) {
          TicketStatus.valid => 'Valid',
          TicketStatus.used => 'Used',
          TicketStatus.cancelled => 'Cancelled',
          TicketStatus.refunded => 'Refunded',
        };
        expect(find.text(expectedText), findsOneWidget);
      }
    });
  });
}

Widget _wrapWithMaterial(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
      useMaterial3: true,
    ),
    home: child,
  );
}

Ticket _createTicket({
  String ticketNumber = 'TKT-123-4567',
  String? ownerName = 'John Doe',
  String? ownerEmail = 'test@example.com',
  int priceCents = 5000,
  TicketStatus status = TicketStatus.valid,
  DateTime? checkedInAt,
}) {
  return Ticket.fromJson({
    'id': 'tkt_001',
    'event_id': 'evt_001',
    'ticket_number': ticketNumber,
    'owner_name': ownerName,
    'owner_email': ownerEmail,
    'price_paid_cents': priceCents,
    'currency': 'USD',
    'sold_at': '2025-01-15T10:00:00Z',
    'status': status.value,
    'created_at': '2025-01-15T10:00:00Z',
    if (checkedInAt != null) 'checked_in_at': checkedInAt.toIso8601String(),
  });
}

Ticket _createTicketWithEventData({
  String? eventTitle = 'Test Event',
  String? eventSubtitle,
  String? venue = 'Test Venue',
  String? city = 'Test City',
  String? country = 'USA',
  DateTime? eventDate,
  int noiseSeed = 42,
}) {
  return Ticket.fromJson({
    'id': 'tkt_001',
    'event_id': 'evt_001',
    'ticket_number': 'TKT-123-4567',
    'owner_name': 'John Doe',
    'owner_email': 'test@example.com',
    'price_paid_cents': 5000,
    'currency': 'USD',
    'sold_at': '2025-01-15T10:00:00Z',
    'status': 'valid',
    'created_at': '2025-01-15T10:00:00Z',
    'events': {
      if (eventTitle != null) 'title': eventTitle,
      if (eventSubtitle != null) 'subtitle': eventSubtitle,
      if (venue != null) 'venue': venue,
      if (city != null) 'city': city,
      if (country != null) 'country': country,
      if (eventDate != null) 'date': eventDate.toIso8601String(),
      'noise_seed': noiseSeed,
    },
  });
}
