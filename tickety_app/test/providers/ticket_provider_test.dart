import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tickety/core/providers/ticket_provider.dart';
import 'package:tickety/features/staff/data/i_ticket_repository.dart';
import 'package:tickety/features/staff/models/ticket.dart';

import '../mocks/mock_repositories.dart';

void main() {
  group('TicketState', () {
    test('initial state has empty values', () {
      const state = TicketState();

      expect(state.tickets, isEmpty);
      expect(state.stats, isNull);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.currentEventId, isNull);
    });

    test('copyWith creates copy with modified values', () {
      final tickets = [_createMockTicket('1')];
      const stats = TicketStats(
        totalSold: 10,
        checkedIn: 5,
        totalRevenueCents: 50000,
      );

      final state = const TicketState().copyWith(
        tickets: tickets,
        stats: stats,
        isLoading: true,
        currentEventId: 'evt_001',
      );

      expect(state.tickets, tickets);
      expect(state.stats, stats);
      expect(state.isLoading, isTrue);
      expect(state.currentEventId, 'evt_001');
    });

    test('copyWith with clearError removes error', () {
      final state = const TicketState().copyWith(error: 'Some error');
      final cleared = state.copyWith(clearError: true);

      expect(cleared.error, isNull);
    });

    test('copyWith with clearStats removes stats', () {
      const stats = TicketStats(
        totalSold: 10,
        checkedIn: 5,
        totalRevenueCents: 50000,
      );
      final state = const TicketState().copyWith(stats: stats);
      final cleared = state.copyWith(clearStats: true);

      expect(cleared.stats, isNull);
    });

    test('getByStatus filters tickets correctly', () {
      final tickets = [
        _createMockTicket('1', status: TicketStatus.valid),
        _createMockTicket('2', status: TicketStatus.valid),
        _createMockTicket('3', status: TicketStatus.used),
        _createMockTicket('4', status: TicketStatus.cancelled),
      ];
      final state = const TicketState().copyWith(tickets: tickets);

      expect(state.getByStatus(TicketStatus.valid).length, 2);
      expect(state.getByStatus(TicketStatus.used).length, 1);
      expect(state.getByStatus(TicketStatus.cancelled).length, 1);
    });

    test('convenience getters return correct tickets', () {
      final tickets = [
        _createMockTicket('1', status: TicketStatus.valid),
        _createMockTicket('2', status: TicketStatus.used),
        _createMockTicket('3', status: TicketStatus.cancelled),
      ];
      final state = const TicketState().copyWith(tickets: tickets);

      expect(state.validTickets.length, 1);
      expect(state.usedTickets.length, 1);
      expect(state.cancelledTickets.length, 1);
    });

    test('totalRevenueCents calculates excluding cancelled', () {
      final tickets = [
        _createMockTicket('1', priceCents: 1000),
        _createMockTicket('2', priceCents: 2000),
        _createMockTicket('3', priceCents: 3000, status: TicketStatus.cancelled),
      ];
      final state = const TicketState().copyWith(tickets: tickets);

      expect(state.totalRevenueCents, 3000); // 1000 + 2000, excluding cancelled
    });

    test('formattedRevenue returns formatted string', () {
      final tickets = [
        _createMockTicket('1', priceCents: 5000),
        _createMockTicket('2', priceCents: 2500),
      ];
      final state = const TicketState().copyWith(tickets: tickets);

      expect(state.formattedRevenue, '\$75.00');
    });
  });

  group('TicketStats', () {
    test('remaining calculates correctly', () {
      const stats = TicketStats(
        totalSold: 100,
        checkedIn: 40,
        totalRevenueCents: 100000,
      );

      expect(stats.remaining, 60);
    });

    test('formattedRevenue formats correctly', () {
      const stats = TicketStats(
        totalSold: 10,
        checkedIn: 5,
        totalRevenueCents: 12345,
      );

      expect(stats.formattedRevenue, '\$123.45');
    });

    test('checkInRate calculates correctly', () {
      const stats = TicketStats(
        totalSold: 100,
        checkedIn: 25,
        totalRevenueCents: 0,
      );

      expect(stats.checkInRate, 0.25);
    });

    test('checkInRate returns 0 when no tickets sold', () {
      const stats = TicketStats(
        totalSold: 0,
        checkedIn: 0,
        totalRevenueCents: 0,
      );

      expect(stats.checkInRate, 0);
    });

    test('checkInPercentage formats correctly', () {
      const stats = TicketStats(
        totalSold: 100,
        checkedIn: 75,
        totalRevenueCents: 0,
      );

      expect(stats.checkInPercentage, '75%');
    });
  });

  group('TicketNotifier', () {
    late MockTicketRepository mockRepository;
    late TicketNotifier notifier;

    setUp(() {
      mockRepository = MockTicketRepository();
      notifier = TicketNotifier(mockRepository);
    });

    test('initial state is empty', () {
      expect(notifier.state.tickets, isEmpty);
      expect(notifier.state.isLoading, isFalse);
    });

    test('loadTickets fetches tickets and stats', () async {
      final tickets = [_createMockTicket('1')];
      const stats = TicketStats(
        totalSold: 1,
        checkedIn: 0,
        totalRevenueCents: 5000,
      );

      when(() => mockRepository.getEventTickets('evt_001'))
          .thenAnswer((_) async => tickets);
      when(() => mockRepository.getTicketStats('evt_001'))
          .thenAnswer((_) async => stats);

      await notifier.loadTickets('evt_001');

      expect(notifier.state.tickets, tickets);
      expect(notifier.state.stats, stats);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.currentEventId, 'evt_001');
    });

    test('loadTickets handles errors', () async {
      when(() => mockRepository.getEventTickets('evt_001'))
          .thenThrow(Exception('Network error'));

      await notifier.loadTickets('evt_001');

      expect(notifier.state.isLoading, isFalse);
      // Error is normalized to user-friendly message
      expect(notifier.state.error, isNotNull);
    });

    test('sellTicket adds ticket to state', () async {
      final newTicket = _createMockTicket('new_1');

      // Set up current event
      when(() => mockRepository.getEventTickets('evt_001'))
          .thenAnswer((_) async => []);
      when(() => mockRepository.getTicketStats('evt_001'))
          .thenAnswer((_) async => const TicketStats(
                totalSold: 0,
                checkedIn: 0,
                totalRevenueCents: 0,
              ));
      await notifier.loadTickets('evt_001');

      when(() => mockRepository.sellTicket(
            eventId: 'evt_001',
            ownerEmail: 'test@example.com',
            ownerName: 'John Doe',
            priceCents: 5000,
            walletAddress: null,
          )).thenAnswer((_) async => newTicket);

      when(() => mockRepository.getTicketStats('evt_001'))
          .thenAnswer((_) async => const TicketStats(
                totalSold: 1,
                checkedIn: 0,
                totalRevenueCents: 5000,
              ));

      final result = await notifier.sellTicket(
        eventId: 'evt_001',
        ownerEmail: 'test@example.com',
        ownerName: 'John Doe',
        priceCents: 5000,
      );

      expect(result, newTicket);
      expect(notifier.state.tickets.contains(newTicket), isTrue);
    });

    test('checkInTicket updates ticket status', () async {
      final ticket = _createMockTicket('1');
      final checkedInTicket = _createMockTicket('1', status: TicketStatus.used);

      when(() => mockRepository.getEventTickets('evt_001'))
          .thenAnswer((_) async => [ticket]);
      when(() => mockRepository.getTicketStats('evt_001'))
          .thenAnswer((_) async => const TicketStats(
                totalSold: 1,
                checkedIn: 0,
                totalRevenueCents: 5000,
              ));
      await notifier.loadTickets('evt_001');

      when(() => mockRepository.checkInTicket('1'))
          .thenAnswer((_) async => checkedInTicket);

      final result = await notifier.checkInTicket('1');

      expect(result, isTrue);
      expect(notifier.state.tickets.first.status, TicketStatus.used);
    });

    test('undoCheckIn reverts ticket status', () async {
      final ticket = _createMockTicket('1', status: TicketStatus.used);
      final validTicket = _createMockTicket('1', status: TicketStatus.valid);

      when(() => mockRepository.getEventTickets('evt_001'))
          .thenAnswer((_) async => [ticket]);
      when(() => mockRepository.getTicketStats('evt_001'))
          .thenAnswer((_) async => const TicketStats(
                totalSold: 1,
                checkedIn: 1,
                totalRevenueCents: 5000,
              ));
      await notifier.loadTickets('evt_001');

      when(() => mockRepository.undoCheckIn('1'))
          .thenAnswer((_) async => validTicket);

      final result = await notifier.undoCheckIn('1');

      expect(result, isTrue);
      expect(notifier.state.tickets.first.status, TicketStatus.valid);
    });

    test('cancelTicket updates ticket status', () async {
      final ticket = _createMockTicket('1');
      final cancelledTicket =
          _createMockTicket('1', status: TicketStatus.cancelled);

      when(() => mockRepository.getEventTickets('evt_001'))
          .thenAnswer((_) async => [ticket]);
      when(() => mockRepository.getTicketStats('evt_001'))
          .thenAnswer((_) async => const TicketStats(
                totalSold: 1,
                checkedIn: 0,
                totalRevenueCents: 5000,
              ));
      await notifier.loadTickets('evt_001');

      when(() => mockRepository.cancelTicket('1'))
          .thenAnswer((_) async => cancelledTicket);

      final result = await notifier.cancelTicket('1');

      expect(result, isTrue);
      expect(notifier.state.tickets.first.status, TicketStatus.cancelled);
    });

    test('clear resets state', () async {
      when(() => mockRepository.getEventTickets('evt_001'))
          .thenAnswer((_) async => [_createMockTicket('1')]);
      when(() => mockRepository.getTicketStats('evt_001'))
          .thenAnswer((_) async => const TicketStats(
                totalSold: 1,
                checkedIn: 0,
                totalRevenueCents: 5000,
              ));
      await notifier.loadTickets('evt_001');

      notifier.clear();

      expect(notifier.state.tickets, isEmpty);
      expect(notifier.state.stats, isNull);
      expect(notifier.state.currentEventId, isNull);
    });
  });

  group('MyTicketsState', () {
    test('initial state is empty', () {
      const state = MyTicketsState();

      expect(state.tickets, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('upcomingTickets filters by date', () {
      final futureDate = DateTime.now().add(const Duration(days: 7));
      final pastDate = DateTime.now().subtract(const Duration(days: 7));

      final tickets = [
        _createMockTicketWithEventDate('1', futureDate),
        _createMockTicketWithEventDate('2', pastDate),
        _createMockTicketWithEventDate('3', futureDate),
      ];
      final state = const MyTicketsState().copyWith(tickets: tickets);

      expect(state.upcomingTickets.length, 2);
    });

    test('pastTickets filters by date', () {
      final futureDate = DateTime.now().add(const Duration(days: 7));
      final pastDate = DateTime.now().subtract(const Duration(days: 7));

      final tickets = [
        _createMockTicketWithEventDate('1', futureDate),
        _createMockTicketWithEventDate('2', pastDate),
        _createMockTicketWithEventDate('3', pastDate),
      ];
      final state = const MyTicketsState().copyWith(tickets: tickets);

      expect(state.pastTickets.length, 2);
    });
  });

  group('MyTicketsNotifier', () {
    late MockTicketRepository mockRepository;
    late MyTicketsNotifier notifier;

    setUp(() {
      mockRepository = MockTicketRepository();
      notifier = MyTicketsNotifier(mockRepository);
    });

    test('load fetches user tickets', () async {
      final tickets = [_createMockTicket('1')];

      when(() => mockRepository.getMyTickets())
          .thenAnswer((_) async => tickets);

      await notifier.load();

      expect(notifier.state.tickets, tickets);
      expect(notifier.state.isLoading, isFalse);
    });

    test('load handles errors', () async {
      when(() => mockRepository.getMyTickets())
          .thenThrow(Exception('Not authenticated'));

      await notifier.load();

      expect(notifier.state.isLoading, isFalse);
      // Error is normalized to user-friendly message
      expect(notifier.state.error, isNotNull);
    });

    test('refresh reloads tickets', () async {
      when(() => mockRepository.getMyTickets())
          .thenAnswer((_) async => [_createMockTicket('1')]);

      await notifier.refresh();

      verify(() => mockRepository.getMyTickets()).called(1);
    });

    test('clearError removes error', () async {
      when(() => mockRepository.getMyTickets())
          .thenThrow(Exception('Error'));
      await notifier.load();

      notifier.clearError();

      expect(notifier.state.error, isNull);
    });
  });
}

Ticket _createMockTicket(
  String id, {
  TicketStatus status = TicketStatus.valid,
  int priceCents = 5000,
}) {
  return Ticket.fromJson({
    'id': id,
    'event_id': 'evt_001',
    'ticket_number': 'TKT-$id',
    'owner_email': 'test@example.com',
    'owner_name': 'Test User',
    'price_paid_cents': priceCents,
    'currency': 'USD',
    'sold_at': '2025-01-15T10:00:00Z',
    'status': status.value,
    'created_at': '2025-01-15T10:00:00Z',
  });
}

Ticket _createMockTicketWithEventDate(String id, DateTime eventDate) {
  return Ticket.fromJson({
    'id': id,
    'event_id': 'evt_001',
    'ticket_number': 'TKT-$id',
    'price_paid_cents': 5000,
    'currency': 'USD',
    'sold_at': '2025-01-15T10:00:00Z',
    'status': 'valid',
    'created_at': '2025-01-15T10:00:00Z',
    'events': {
      'date': eventDate.toIso8601String(),
    },
  });
}
