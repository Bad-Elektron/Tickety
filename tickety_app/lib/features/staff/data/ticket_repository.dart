import 'dart:math';

import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/ticket.dart';
import 'i_ticket_repository.dart';

export 'i_ticket_repository.dart' show TicketStats, ITicketRepository;

const _tag = 'TicketRepository';

/// Supabase implementation of [ITicketRepository].
class TicketRepository implements ITicketRepository {
  final _client = SupabaseService.instance.client;

  @override
  Future<Ticket> sellTicket({
    required String eventId,
    required String? ownerEmail,
    required String? ownerName,
    required int priceCents,
    String? walletAddress,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;

    // Generate unique ticket number
    final ticketNumber = _generateTicketNumber();

    AppLogger.debug(
      'Selling ticket: event=$eventId, price=$priceCents cents, number=$ticketNumber',
      tag: _tag,
    );

    final response = await _client
        .from('tickets')
        .insert({
          'event_id': eventId,
          'ticket_number': ticketNumber,
          'owner_email': ownerEmail,
          'owner_name': ownerName,
          'owner_wallet_address': walletAddress,
          'price_paid_cents': priceCents,
          'currency': 'USD',
          'sold_by': userId,
          'status': 'valid',
        })
        .select()
        .single();

    AppLogger.info('Ticket sold: $ticketNumber', tag: _tag);
    return Ticket.fromJson(response);
  }

  @override
  Future<List<Ticket>> getEventTickets(String eventId) async {
    AppLogger.debug('Fetching tickets for event: $eventId', tag: _tag);

    final response = await _client
        .from('tickets')
        .select()
        .eq('event_id', eventId)
        .order('sold_at', ascending: false);

    final tickets = (response as List<dynamic>)
        .map((json) => Ticket.fromJson(json as Map<String, dynamic>))
        .toList();

    AppLogger.debug('Fetched ${tickets.length} tickets', tag: _tag);
    return tickets;
  }

  @override
  Future<Ticket?> getTicket(String eventId, String ticketIdOrNumber) async {
    AppLogger.debug(
      'Looking up ticket: $ticketIdOrNumber for event $eventId',
      tag: _tag,
    );

    // Try by ID first
    var response = await _client
        .from('tickets')
        .select()
        .eq('event_id', eventId)
        .eq('id', ticketIdOrNumber)
        .maybeSingle();

    // Try by ticket number if not found by ID
    if (response == null) {
      AppLogger.debug('Not found by ID, trying ticket number', tag: _tag);
      response = await _client
          .from('tickets')
          .select()
          .eq('event_id', eventId)
          .eq('ticket_number', ticketIdOrNumber)
          .maybeSingle();
    }

    if (response == null) {
      AppLogger.debug('Ticket not found: $ticketIdOrNumber', tag: _tag);
      return null;
    }

    final ticket = Ticket.fromJson(response);
    AppLogger.debug(
      'Found ticket: ${ticket.ticketNumber} (status: ${ticket.status.value})',
      tag: _tag,
    );
    return ticket;
  }

  @override
  Future<Ticket> checkInTicket(String ticketId) async {
    final userId = SupabaseService.instance.currentUser?.id;

    AppLogger.debug('Checking in ticket: $ticketId', tag: _tag);

    final response = await _client
        .from('tickets')
        .update({
          'checked_in_at': DateTime.now().toUtc().toIso8601String(),
          'checked_in_by': userId,
          'status': 'used',
        })
        .eq('id', ticketId)
        .select()
        .single();

    final ticket = Ticket.fromJson(response);
    AppLogger.info('Ticket checked in: ${ticket.ticketNumber}', tag: _tag);
    return ticket;
  }

  @override
  Future<Ticket> undoCheckIn(String ticketId) async {
    AppLogger.debug('Undoing check-in for ticket: $ticketId', tag: _tag);

    final response = await _client
        .from('tickets')
        .update({
          'checked_in_at': null,
          'checked_in_by': null,
          'status': 'valid',
        })
        .eq('id', ticketId)
        .select()
        .single();

    final ticket = Ticket.fromJson(response);
    AppLogger.info('Check-in undone: ${ticket.ticketNumber}', tag: _tag);
    return ticket;
  }

  @override
  Future<Ticket> cancelTicket(String ticketId) async {
    AppLogger.debug('Cancelling ticket: $ticketId', tag: _tag);

    final response = await _client
        .from('tickets')
        .update({'status': 'cancelled'})
        .eq('id', ticketId)
        .select()
        .single();

    final ticket = Ticket.fromJson(response);
    AppLogger.info('Ticket cancelled: ${ticket.ticketNumber}', tag: _tag);
    return ticket;
  }

  @override
  Future<TicketStats> getTicketStats(String eventId) async {
    AppLogger.debug('Fetching ticket stats for event: $eventId', tag: _tag);

    final response = await _client
        .from('tickets')
        .select('status, price_paid_cents')
        .eq('event_id', eventId);

    final tickets = response as List<dynamic>;

    int totalSold = tickets.length;
    int checkedIn = 0;
    int totalRevenueCents = 0;

    for (final ticket in tickets) {
      if (ticket['status'] == 'used') checkedIn++;
      totalRevenueCents += ticket['price_paid_cents'] as int;
    }

    AppLogger.debug(
      'Stats: $totalSold sold, $checkedIn checked in, \$${totalRevenueCents / 100} revenue',
      tag: _tag,
    );

    return TicketStats(
      totalSold: totalSold,
      checkedIn: checkedIn,
      totalRevenueCents: totalRevenueCents,
    );
  }

  @override
  Future<List<Ticket>> getMyTickets() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.debug('No current user for my tickets', tag: _tag);
      return [];
    }

    AppLogger.debug('Fetching tickets for user: $userId', tag: _tag);

    // Query tickets where user is the buyer (sold_by = user purchasing for themselves)
    // The sold_by field is set by the webhook when payment succeeds
    final response = await _client
        .from('tickets')
        .select('*, events(*)')
        .eq('sold_by', userId)
        .order('sold_at', ascending: false);

    final tickets = (response as List<dynamic>)
        .map((json) => Ticket.fromJson(json as Map<String, dynamic>))
        .toList();

    AppLogger.debug('Found ${tickets.length} user tickets', tag: _tag);
    return tickets;
  }

  String _generateTicketNumber() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    final randomPart = random.nextInt(9999).toString().padLeft(4, '0');
    return 'TKT-$timestamp-$randomPart';
  }
}
