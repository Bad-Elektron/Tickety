import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/events/widgets/ticket_info_card.dart';
import 'package:tickety/features/staff/models/ticket.dart';

void main() {
  group('TicketInfoCard', () {
    testWidgets('displays ticket holder name', (tester) async {
      final ticket = _createTicket(ownerName: 'John Doe');

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Ticket Holder'), findsOneWidget);
    });

    testWidgets('displays Guest when no owner name', (tester) async {
      final ticket = _createTicket(ownerName: null);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('Guest'), findsOneWidget);
    });

    testWidgets('displays ticket number', (tester) async {
      final ticket = _createTicket(ticketNumber: 'TKT-123456-7890');

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('TKT-123456-7890'), findsOneWidget);
      expect(find.text('Ticket Number'), findsOneWidget);
    });

    testWidgets('displays email when present', (tester) async {
      final ticket = _createTicket(ownerEmail: 'test@example.com');

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('hides email row when email is null', (tester) async {
      final ticket = _createTicket(ownerEmail: null);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('Email'), findsNothing);
    });

    testWidgets('displays formatted price', (tester) async {
      final ticket = _createTicket(priceCents: 5000);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text(ticket.formattedPrice), findsOneWidget);
      expect(find.text('Price Paid'), findsOneWidget);
    });

    testWidgets('displays valid status for valid ticket', (tester) async {
      final ticket = _createTicket(status: TicketStatus.valid);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('Valid Ticket'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('displays already used status for used ticket', (tester) async {
      final ticket = _createTicket(
        status: TicketStatus.used,
        checkedInAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('Already Checked In'), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });

    testWidgets('displays cancelled status for cancelled ticket', (tester) async {
      final ticket = _createTicket(status: TicketStatus.cancelled);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('Ticket Cancelled'), findsOneWidget);
      expect(find.byIcon(Icons.block), findsOneWidget);
    });

    testWidgets('displays check-in time for used ticket', (tester) async {
      final checkedInAt = DateTime.now().subtract(const Duration(minutes: 30));
      final ticket = _createTicket(
        status: TicketStatus.used,
        checkedInAt: checkedInAt,
      );

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      // Should show the check-in history
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.textContaining('Checked in'), findsOneWidget);
    });

    testWidgets('shows Check In button for valid ticket', (tester) async {
      final ticket = _createTicket(status: TicketStatus.valid);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('Check In'), findsOneWidget);
    });

    testWidgets('hides Check In button for used ticket', (tester) async {
      final ticket = _createTicket(status: TicketStatus.used);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('Check In'), findsNothing);
    });

    testWidgets('hides Check In button for cancelled ticket', (tester) async {
      final ticket = _createTicket(status: TicketStatus.cancelled);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(ticket: ticket),
      ));

      expect(find.text('Check In'), findsNothing);
    });

    testWidgets('calls onDismiss when Dismiss button is tapped', (tester) async {
      bool dismissed = false;
      final ticket = _createTicket();

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(
          ticket: ticket,
          onDismiss: () => dismissed = true,
        ),
      ));

      await tester.tap(find.text('Dismiss'));
      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets('calls onCheckIn when Check In button is tapped', (tester) async {
      bool checkedIn = false;
      final ticket = _createTicket(status: TicketStatus.valid);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(
          ticket: ticket,
          onCheckIn: () => checkedIn = true,
        ),
      ));

      await tester.tap(find.text('Check In'));
      await tester.pump();

      expect(checkedIn, isTrue);
    });

    testWidgets('shows loading state during check-in', (tester) async {
      final ticket = _createTicket(status: TicketStatus.valid);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(
          ticket: ticket,
          isLoading: true,
        ),
      ));

      expect(find.text('Checking in...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('disables buttons during loading', (tester) async {
      final ticket = _createTicket(status: TicketStatus.valid);
      bool dismissed = false;
      bool checkedIn = false;

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(
          ticket: ticket,
          isLoading: true,
          onDismiss: () => dismissed = true,
          onCheckIn: () => checkedIn = true,
        ),
      ));

      // Try tapping buttons
      await tester.tap(find.text('Dismiss'));
      await tester.tap(find.text('Checking in...'));
      await tester.pump();

      // Callbacks should not be called when loading
      expect(dismissed, isFalse);
      expect(checkedIn, isFalse);
    });

    testWidgets('uses override validation status when provided', (tester) async {
      final ticket = _createTicket(status: TicketStatus.valid);

      await tester.pumpWidget(_wrapWithMaterial(
        TicketInfoCard(
          ticket: ticket,
          validationStatus: CheckInValidationStatus.wrongEvent,
        ),
      ));

      // Should show wrong event status despite ticket being valid
      expect(find.text('Wrong Event'), findsOneWidget);
      expect(find.byIcon(Icons.event_note), findsOneWidget);
    });
  });
}

Widget _wrapWithMaterial(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
      useMaterial3: true,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: child,
      ),
    ),
  );
}

Ticket _createTicket({
  String? ownerName = 'John Doe',
  String? ownerEmail = 'test@example.com',
  String ticketNumber = 'TKT-123456-7890',
  int priceCents = 5000,
  TicketStatus status = TicketStatus.valid,
  DateTime? checkedInAt,
}) {
  return Ticket.fromJson({
    'id': 'tkt_001',
    'event_id': 'evt_001',
    'ticket_number': ticketNumber,
    'owner_email': ownerEmail,
    'owner_name': ownerName,
    'price_paid_cents': priceCents,
    'currency': 'USD',
    'sold_at': '2025-01-15T10:00:00Z',
    'status': status.value,
    'created_at': '2025-01-15T10:00:00Z',
    if (checkedInAt != null) 'checked_in_at': checkedInAt.toIso8601String(),
  });
}
