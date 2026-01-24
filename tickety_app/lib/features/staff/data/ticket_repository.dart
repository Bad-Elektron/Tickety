import 'dart:math';

import '../../../core/services/services.dart';
import '../models/ticket.dart';

/// Repository for ticket operations.
class TicketRepository {
  final _client = SupabaseService.instance.client;

  /// Sell a ticket (create ticket record).
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

    return Ticket.fromJson(response);
  }

  /// Get tickets sold for an event.
  Future<List<Ticket>> getEventTickets(String eventId) async {
    final response = await _client
        .from('tickets')
        .select()
        .eq('event_id', eventId)
        .order('sold_at', ascending: false);

    return (response as List<dynamic>)
        .map((json) => Ticket.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get ticket by ID or ticket number.
  Future<Ticket?> getTicket(String eventId, String ticketIdOrNumber) async {
    // Try by ID first
    var response = await _client
        .from('tickets')
        .select()
        .eq('event_id', eventId)
        .eq('id', ticketIdOrNumber)
        .maybeSingle();

    // Try by ticket number if not found by ID
    response ??= await _client
        .from('tickets')
        .select()
        .eq('event_id', eventId)
        .eq('ticket_number', ticketIdOrNumber)
        .maybeSingle();

    if (response == null) return null;
    return Ticket.fromJson(response);
  }

  /// Check in a ticket.
  Future<Ticket> checkInTicket(String ticketId) async {
    final userId = SupabaseService.instance.currentUser?.id;

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

    return Ticket.fromJson(response);
  }

  /// Undo check-in (revert ticket to valid).
  Future<Ticket> undoCheckIn(String ticketId) async {
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

    return Ticket.fromJson(response);
  }

  /// Cancel a ticket.
  Future<Ticket> cancelTicket(String ticketId) async {
    final response = await _client
        .from('tickets')
        .update({'status': 'cancelled'})
        .eq('id', ticketId)
        .select()
        .single();

    return Ticket.fromJson(response);
  }

  /// Get ticket stats for an event.
  Future<TicketStats> getTicketStats(String eventId) async {
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

    return TicketStats(
      totalSold: totalSold,
      checkedIn: checkedIn,
      totalRevenueCents: totalRevenueCents,
    );
  }

  /// Get tickets for current user (purchased tickets).
  Future<List<Ticket>> getMyTickets() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return [];

    // For now, get tickets by email matching user's email
    final userEmail = SupabaseService.instance.currentUser?.email;
    if (userEmail == null) return [];

    final response = await _client
        .from('tickets')
        .select('*, events(*)')
        .eq('owner_email', userEmail)
        .order('sold_at', ascending: false);

    return (response as List<dynamic>)
        .map((json) => Ticket.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  String _generateTicketNumber() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    final randomPart = random.nextInt(9999).toString().padLeft(4, '0');
    return 'TKT-$timestamp-$randomPart';
  }
}

/// Statistics for tickets at an event.
class TicketStats {
  final int totalSold;
  final int checkedIn;
  final int totalRevenueCents;

  const TicketStats({
    required this.totalSold,
    required this.checkedIn,
    required this.totalRevenueCents,
  });

  /// Tickets not yet checked in.
  int get remaining => totalSold - checkedIn;

  /// Formatted revenue string.
  String get formattedRevenue {
    final dollars = totalRevenueCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Check-in rate as percentage (0.0 - 1.0).
  double get checkInRate => totalSold > 0 ? checkedIn / totalSold : 0;

  /// Check-in rate as percentage string.
  String get checkInPercentage => '${(checkInRate * 100).toStringAsFixed(0)}%';
}
