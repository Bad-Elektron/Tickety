import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/staff/data/ticket_repository.dart';
import '../../features/staff/models/ticket.dart';

/// State for event ticket management.
class TicketState {
  final List<Ticket> tickets;
  final TicketStats? stats;
  final bool isLoading;
  final String? error;
  final String? currentEventId;

  const TicketState({
    this.tickets = const [],
    this.stats,
    this.isLoading = false,
    this.error,
    this.currentEventId,
  });

  TicketState copyWith({
    List<Ticket>? tickets,
    TicketStats? stats,
    bool? isLoading,
    String? error,
    String? currentEventId,
    bool clearError = false,
    bool clearStats = false,
  }) {
    return TicketState(
      tickets: tickets ?? this.tickets,
      stats: clearStats ? null : (stats ?? this.stats),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      currentEventId: currentEventId ?? this.currentEventId,
    );
  }

  /// Get tickets by status.
  List<Ticket> getByStatus(TicketStatus status) {
    return tickets.where((t) => t.status == status).toList();
  }

  /// Valid tickets (not used, not cancelled).
  List<Ticket> get validTickets => getByStatus(TicketStatus.valid);

  /// Used/checked-in tickets.
  List<Ticket> get usedTickets => getByStatus(TicketStatus.used);

  /// Cancelled tickets.
  List<Ticket> get cancelledTickets => getByStatus(TicketStatus.cancelled);

  /// Total revenue in cents.
  int get totalRevenueCents {
    return tickets
        .where((t) => t.status != TicketStatus.cancelled)
        .fold(0, (sum, t) => sum + t.pricePaidCents);
  }

  /// Formatted revenue string.
  String get formattedRevenue {
    final dollars = totalRevenueCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }
}

/// Notifier for managing event tickets.
class TicketNotifier extends StateNotifier<TicketState> {
  final TicketRepository _repository;

  TicketNotifier(this._repository) : super(const TicketState());

  /// Load tickets for a specific event.
  Future<void> loadTickets(String eventId) async {
    if (state.isLoading && state.currentEventId == eventId) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentEventId: eventId,
    );

    try {
      final tickets = await _repository.getEventTickets(eventId);
      final stats = await _repository.getTicketStats(eventId);

      state = state.copyWith(
        tickets: tickets,
        stats: stats,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load only stats for an event (lighter operation).
  Future<void> loadStats(String eventId) async {
    try {
      final stats = await _repository.getTicketStats(eventId);
      state = state.copyWith(stats: stats);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Refresh tickets for current event.
  Future<void> refresh() async {
    final eventId = state.currentEventId;
    if (eventId == null) return;
    await loadTickets(eventId);
  }

  /// Sell a new ticket.
  Future<Ticket?> sellTicket({
    required String eventId,
    String? ownerName,
    String? ownerEmail,
    required int priceCents,
    String? walletAddress,
  }) async {
    try {
      final ticket = await _repository.sellTicket(
        eventId: eventId,
        ownerName: ownerName,
        ownerEmail: ownerEmail,
        priceCents: priceCents,
        walletAddress: walletAddress,
      );

      // Add to local state immediately
      state = state.copyWith(
        tickets: [ticket, ...state.tickets],
      );

      // Update stats
      if (state.currentEventId == eventId) {
        await loadStats(eventId);
      }

      return ticket;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Check in a ticket.
  Future<bool> checkInTicket(String ticketId) async {
    try {
      final updated = await _repository.checkInTicket(ticketId);

      // Update in local state
      state = state.copyWith(
        tickets: state.tickets.map((t) {
          return t.id == ticketId ? updated : t;
        }).toList(),
      );

      // Update stats
      if (state.currentEventId != null) {
        await loadStats(state.currentEventId!);
      }

      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Undo check-in for a ticket.
  Future<bool> undoCheckIn(String ticketId) async {
    try {
      final updated = await _repository.undoCheckIn(ticketId);

      // Update in local state
      state = state.copyWith(
        tickets: state.tickets.map((t) {
          return t.id == ticketId ? updated : t;
        }).toList(),
      );

      // Update stats
      if (state.currentEventId != null) {
        await loadStats(state.currentEventId!);
      }

      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Cancel a ticket.
  Future<bool> cancelTicket(String ticketId) async {
    try {
      final updated = await _repository.cancelTicket(ticketId);

      // Update in local state
      state = state.copyWith(
        tickets: state.tickets.map((t) {
          return t.id == ticketId ? updated : t;
        }).toList(),
      );

      // Update stats
      if (state.currentEventId != null) {
        await loadStats(state.currentEventId!);
      }

      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Find a ticket by ID or ticket number.
  Future<Ticket?> findTicket(String eventId, String ticketIdOrNumber) async {
    try {
      return await _repository.getTicket(eventId, ticketIdOrNumber);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Clear error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Clear all state (when leaving event context).
  void clear() {
    state = const TicketState();
  }
}

/// State for user's own tickets (as an attendee).
class MyTicketsState {
  final List<Ticket> tickets;
  final bool isLoading;
  final String? error;

  const MyTicketsState({
    this.tickets = const [],
    this.isLoading = false,
    this.error,
  });

  MyTicketsState copyWith({
    List<Ticket>? tickets,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return MyTicketsState(
      tickets: tickets ?? this.tickets,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Upcoming tickets (events in the future).
  List<Ticket> get upcomingTickets {
    final now = DateTime.now();
    return tickets.where((t) {
      final eventDate = t.eventData?['date'];
      if (eventDate == null) return true;
      final date = DateTime.tryParse(eventDate.toString());
      return date == null || date.isAfter(now);
    }).toList();
  }

  /// Past tickets (events already happened).
  List<Ticket> get pastTickets {
    final now = DateTime.now();
    return tickets.where((t) {
      final eventDate = t.eventData?['date'];
      if (eventDate == null) return false;
      final date = DateTime.tryParse(eventDate.toString());
      return date != null && date.isBefore(now);
    }).toList();
  }
}

/// Notifier for user's own tickets.
class MyTicketsNotifier extends StateNotifier<MyTicketsState> {
  final TicketRepository _repository;

  MyTicketsNotifier(this._repository) : super(const MyTicketsState());

  /// Load user's tickets.
  Future<void> load() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final tickets = await _repository.getMyTickets();
      state = state.copyWith(
        tickets: tickets,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Refresh tickets.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: false);
    await load();
  }

  /// Clear error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ============================================================
// PROVIDERS
// ============================================================

/// Repository provider - can be overridden for testing.
final ticketRepositoryProvider = Provider<TicketRepository>((ref) {
  return TicketRepository();
});

/// Main ticket provider for event ticket management (staff view).
final ticketProvider =
    StateNotifierProvider<TicketNotifier, TicketState>((ref) {
  final repository = ref.watch(ticketRepositoryProvider);
  return TicketNotifier(repository);
});

/// Provider for user's own tickets (attendee view).
final myTicketsProvider =
    StateNotifierProvider<MyTicketsNotifier, MyTicketsState>((ref) {
  final repository = ref.watch(ticketRepositoryProvider);
  return MyTicketsNotifier(repository);
});

/// Convenience provider for ticket stats.
final ticketStatsProvider = Provider<TicketStats?>((ref) {
  return ref.watch(ticketProvider).stats;
});

/// Convenience provider for checking if tickets are loading.
final ticketsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(ticketProvider).isLoading;
});

/// Convenience provider for total tickets sold.
final ticketsSoldProvider = Provider<int>((ref) {
  return ref.watch(ticketProvider).tickets.length;
});

/// Convenience provider for checked-in count.
final ticketsCheckedInProvider = Provider<int>((ref) {
  return ref.watch(ticketProvider).usedTickets.length;
});
