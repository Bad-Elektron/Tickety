import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/favor_tickets/data/favor_ticket_repository.dart';
import '../../features/favor_tickets/models/ticket_offer.dart';
import '../errors/errors.dart';

const _tag = 'FavorTicketProvider';

/// Repository provider.
final favorTicketRepositoryProvider = Provider<FavorTicketRepository>((ref) {
  return FavorTicketRepository();
});

/// State for pending ticket offers (recipient view).
class PendingOffersState {
  final List<TicketOffer> offers;
  final bool isLoading;
  final String? error;

  const PendingOffersState({
    this.offers = const [],
    this.isLoading = false,
    this.error,
  });

  PendingOffersState copyWith({
    List<TicketOffer>? offers,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return PendingOffersState(
      offers: offers ?? this.offers,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier for pending offers the current user has received.
class PendingOffersNotifier extends StateNotifier<PendingOffersState> {
  final FavorTicketRepository _repository;

  PendingOffersNotifier(this._repository) : super(const PendingOffersState());

  /// Load pending offers.
  Future<void> load() async {
    if (state.isLoading) return;

    AppLogger.debug('Loading pending offers', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final offers = await _repository.getMyPendingOffers();
      AppLogger.info('Loaded ${offers.length} pending offers', tag: _tag);
      state = state.copyWith(offers: offers, isLoading: false);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load pending offers',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
    }
  }

  /// Refresh offers.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: false);
    await load();
  }

  /// Remove an offer from local state (after accept/decline).
  void removeOffer(String offerId) {
    state = state.copyWith(
      offers: state.offers.where((o) => o.id != offerId).toList(),
    );
  }
}

/// Provider for pending offers.
final pendingOffersProvider =
    StateNotifierProvider<PendingOffersNotifier, PendingOffersState>((ref) {
  final repository = ref.watch(favorTicketRepositoryProvider);
  return PendingOffersNotifier(repository);
});
