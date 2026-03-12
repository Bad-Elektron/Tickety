import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/waitlist/data/waitlist_repository.dart';
import '../../features/waitlist/models/waitlist_entry.dart';

/// Repository provider.
final waitlistRepositoryProvider = Provider<WaitlistRepository>((ref) {
  return WaitlistRepository();
});

/// State for waitlist UI.
class WaitlistState {
  final WaitlistEntry? entry;
  final bool isLoading;
  final String? error;
  final int? position;

  const WaitlistState({
    this.entry,
    this.isLoading = false,
    this.error,
    this.position,
  });

  WaitlistState copyWith({
    WaitlistEntry? entry,
    bool? isLoading,
    String? error,
    int? position,
    bool clearEntry = false,
    bool clearError = false,
  }) {
    return WaitlistState(
      entry: clearEntry ? null : (entry ?? this.entry),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      position: position ?? this.position,
    );
  }

  bool get isOnWaitlist => entry != null && entry!.isActive;
  bool get isAutoBuy => entry?.isAutoBuy ?? false;
  bool get isNotify => entry?.isNotify ?? false;
}

/// Manages waitlist state for a specific event.
class WaitlistNotifier extends StateNotifier<WaitlistState> {
  final WaitlistRepository _repository;
  final String eventId;

  WaitlistNotifier(this._repository, this.eventId)
      : super(const WaitlistState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final entry = await _repository.getMyEntry(eventId);
      int? position;
      if (entry != null) {
        position = await _repository.getPosition(eventId);
      }
      state = WaitlistState(entry: entry, position: position);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> joinNotify() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final entry = await _repository.joinNotify(eventId);
      final position = await _repository.getPosition(eventId);
      state = WaitlistState(entry: entry, position: position);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().contains('duplicate')
            ? 'You are already on the waitlist'
            : 'Failed to join waitlist',
      );
    }
  }

  Future<void> joinAutoBuy({
    required int maxPriceCents,
    required String paymentMethodId,
    required String stripeCustomerId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final entry = await _repository.joinAutoBuy(
        eventId: eventId,
        maxPriceCents: maxPriceCents,
        paymentMethodId: paymentMethodId,
        stripeCustomerId: stripeCustomerId,
      );
      final position = await _repository.getPosition(eventId);
      state = WaitlistState(entry: entry, position: position);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().contains('duplicate')
            ? 'You are already on the waitlist'
            : 'Failed to join waitlist',
      );
    }
  }

  Future<void> leave() async {
    final entry = state.entry;
    if (entry == null) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.cancel(entry.id);
      state = const WaitlistState();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to leave waitlist');
    }
  }
}

/// Family provider keyed by eventId.
final waitlistProvider =
    StateNotifierProvider.autoDispose.family<WaitlistNotifier, WaitlistState, String>(
  (ref, eventId) {
    final repository = ref.watch(waitlistRepositoryProvider);
    return WaitlistNotifier(repository, eventId);
  },
);

/// Waitlist count provider for an event.
final waitlistCountProvider =
    FutureProvider.autoDispose.family<WaitlistCount, String>((ref, eventId) async {
  final repository = ref.watch(waitlistRepositoryProvider);
  return repository.getWaitlistCount(eventId);
});
