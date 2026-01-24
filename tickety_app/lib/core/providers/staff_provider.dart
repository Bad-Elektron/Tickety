import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/staff/data/staff_repository.dart';
import '../../features/staff/models/staff_role.dart';

/// State for event staff management.
class StaffState {
  final List<EventStaff> staff;
  final bool isLoading;
  final String? error;
  final String? currentEventId;

  const StaffState({
    this.staff = const [],
    this.isLoading = false,
    this.error,
    this.currentEventId,
  });

  StaffState copyWith({
    List<EventStaff>? staff,
    bool? isLoading,
    String? error,
    String? currentEventId,
    bool clearError = false,
  }) {
    return StaffState(
      staff: staff ?? this.staff,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      currentEventId: currentEventId ?? this.currentEventId,
    );
  }

  /// Get staff by role.
  List<EventStaff> getByRole(StaffRole role) {
    return staff.where((s) => s.role == role).toList();
  }

  /// Get ushers only.
  List<EventStaff> get ushers => getByRole(StaffRole.usher);

  /// Get sellers only.
  List<EventStaff> get sellers => getByRole(StaffRole.seller);

  /// Get managers only.
  List<EventStaff> get managers => getByRole(StaffRole.manager);

  /// Count by role.
  int get usherCount => ushers.length;
  int get sellerCount => sellers.length;
  int get managerCount => managers.length;
  int get totalCount => staff.length;
}

/// Notifier for managing event staff.
class StaffNotifier extends StateNotifier<StaffState> {
  final StaffRepository _repository;

  StaffNotifier(this._repository) : super(const StaffState());

  /// Load staff for a specific event.
  Future<void> loadStaff(String eventId) async {
    // If already loading this event, skip
    if (state.isLoading && state.currentEventId == eventId) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentEventId: eventId,
    );

    try {
      final staff = await _repository.getEventStaff(eventId);
      state = state.copyWith(
        staff: staff,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Refresh staff for current event.
  Future<void> refresh() async {
    final eventId = state.currentEventId;
    if (eventId == null) return;
    await loadStaff(eventId);
  }

  /// Add a staff member to the current event.
  Future<bool> addStaff({
    required String userId,
    required StaffRole role,
    String? email,
  }) async {
    final eventId = state.currentEventId;
    if (eventId == null) return false;

    try {
      final newStaff = await _repository.addStaff(
        eventId: eventId,
        userId: userId,
        role: role,
        email: email,
      );

      // Add to local state immediately
      state = state.copyWith(
        staff: [newStaff, ...state.staff],
      );

      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Remove a staff member.
  Future<bool> removeStaff(String staffId) async {
    try {
      await _repository.removeStaff(staffId);

      // Remove from local state immediately
      state = state.copyWith(
        staff: state.staff.where((s) => s.id != staffId).toList(),
      );

      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Clear error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Clear all state (when leaving event context).
  void clear() {
    state = const StaffState();
  }
}

/// State for user search results.
class UserSearchState {
  final List<UserSearchResult> results;
  final bool isSearching;
  final String? error;

  const UserSearchState({
    this.results = const [],
    this.isSearching = false,
    this.error,
  });

  UserSearchState copyWith({
    List<UserSearchResult>? results,
    bool? isSearching,
    String? error,
    bool clearError = false,
  }) {
    return UserSearchState(
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier for user search (when adding staff).
class UserSearchNotifier extends StateNotifier<UserSearchState> {
  final StaffRepository _repository;

  UserSearchNotifier(this._repository) : super(const UserSearchState());

  /// Search users by email.
  Future<void> search(String query, {Set<String>? excludeUserIds}) async {
    if (query.trim().length < 2) {
      state = state.copyWith(results: []);
      return;
    }

    state = state.copyWith(isSearching: true, clearError: true);

    try {
      final results = await _repository.searchUsersByEmail(query);

      // Filter out excluded users (already on staff)
      final filtered = excludeUserIds != null
          ? results.where((r) => !excludeUserIds.contains(r.id)).toList()
          : results;

      state = state.copyWith(
        results: filtered,
        isSearching: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSearching: false,
        error: e.toString(),
      );
    }
  }

  /// Clear search results.
  void clear() {
    state = const UserSearchState();
  }
}

// ============================================================
// PROVIDERS
// ============================================================

/// Repository provider - can be overridden for testing.
final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository();
});

/// Main staff provider for event staff management.
final staffProvider = StateNotifierProvider<StaffNotifier, StaffState>((ref) {
  final repository = ref.watch(staffRepositoryProvider);
  return StaffNotifier(repository);
});

/// User search provider for adding new staff.
final userSearchProvider =
    StateNotifierProvider<UserSearchNotifier, UserSearchState>((ref) {
  final repository = ref.watch(staffRepositoryProvider);
  return UserSearchNotifier(repository);
});

/// Convenience provider for staff count.
final staffCountProvider = Provider<int>((ref) {
  return ref.watch(staffProvider).totalCount;
});

/// Convenience provider for checking if staff is loading.
final staffLoadingProvider = Provider<bool>((ref) {
  return ref.watch(staffProvider).isLoading;
});
