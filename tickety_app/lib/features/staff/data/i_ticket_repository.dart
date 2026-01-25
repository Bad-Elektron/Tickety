import '../models/ticket.dart';

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

/// Abstract repository interface for ticket operations.
///
/// Defines the contract for managing event tickets (sales, check-in, etc).
/// Implementations can use different data sources (Supabase, mock, etc).
abstract class ITicketRepository {
  /// Sell a ticket (create ticket record).
  Future<Ticket> sellTicket({
    required String eventId,
    required String? ownerEmail,
    required String? ownerName,
    required int priceCents,
    String? walletAddress,
  });

  /// Get tickets sold for an event.
  Future<List<Ticket>> getEventTickets(String eventId);

  /// Get ticket by ID or ticket number.
  Future<Ticket?> getTicket(String eventId, String ticketIdOrNumber);

  /// Check in a ticket.
  Future<Ticket> checkInTicket(String ticketId);

  /// Undo check-in (revert ticket to valid).
  Future<Ticket> undoCheckIn(String ticketId);

  /// Cancel a ticket.
  Future<Ticket> cancelTicket(String ticketId);

  /// Get ticket stats for an event.
  Future<TicketStats> getTicketStats(String eventId);

  /// Get tickets for current user (purchased tickets).
  Future<List<Ticket>> getMyTickets();
}
