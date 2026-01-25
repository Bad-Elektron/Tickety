import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/staff/data/staff_repository.dart';
import '../../features/staff/models/staff_role.dart';
import '../errors/errors.dart';

const _tag = 'StaffProvider';

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
  final IStaffRepository _repository;

  StaffNotifier(this._repository) : super(const StaffState());

  /// Load staff for a specific event.
  Future<void> loadStaff(String eventId) async {
    // If already loading this event, skip
    if (state.isLoading && state.currentEventId == eventId) return;

    AppLogger.debug('Loading staff for event: $eventId', tag: _tag);

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentEventId: eventId,
    );

    try {
      final staff = await _repository.getEventStaff(eventId);
      AppLogger.info(
        'Loaded ${staff.length} staff members for event $eventId',
        tag: _tag,
      );
      state = state.copyWith(
        staff: staff,
        isLoading: false,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load staff for event $eventId',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
    }
  }

  /// Refresh staff for current event.
  Future<void> refresh() async {
    final eventId = state.currentEventId;
    if (eventId == null) {
      AppLogger.warning('Refresh called with no current event', tag: _tag);
      return;
    }
    await loadStaff(eventId);
  }

  /// Add a staff member to the current event.
  Future<bool> addStaff({
    required String userId,
    required StaffRole role,
    String? email,
  }) async {
    final eventId = state.currentEventId;
    if (eventId == null) {
      AppLogger.warning('Cannot add staff: no current event', tag: _tag);
      return false;
    }

    AppLogger.info(
      'Adding staff member (role: ${role.value}) to event $eventId',
      tag: _tag,
    );

    try {
      final newStaff = await _repository.addStaff(
        eventId: eventId,
        userId: userId,
        role: role,
        email: email,
      );

      AppLogger.info(
        'Staff member added: ${newStaff.userName ?? newStaff.userEmail ?? newStaff.userId}',
        tag: _tag,
      );

      // Add to local state immediately
      state = state.copyWith(
        staff: [newStaff, ...state.staff],
      );

      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to add staff member to event $eventId',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(error: appError.userMessage);
      return false;
    }
  }

  /// Remove a staff member.
  Future<bool> removeStaff(String staffId) async {
    AppLogger.info('Removing staff member: $staffId', tag: _tag);

    try {
      await _repository.removeStaff(staffId);

      AppLogger.info('Staff member removed: $staffId', tag: _tag);

      // Remove from local state immediately
      state = state.copyWith(
        staff: state.staff.where((s) => s.id != staffId).toList(),
      );

      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to remove staff member $staffId',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(error: appError.userMessage);
      return false;
    }
  }

  /// Clear error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Clear all state (when leaving event context).
  void clear() {
    AppLogger.debug('Clearing staff state', tag: _tag);
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
  final IStaffRepository _repository;

  UserSearchNotifier(this._repository) : super(const UserSearchState());

  /// Search users by email.
  Future<void> search(String query, {Set<String>? excludeUserIds}) async {
    if (query.trim().length < 2) {
      state = state.copyWith(results: []);
      return;
    }

    AppLogger.debug('Searching users with query: $query', tag: _tag);
    state = state.copyWith(isSearching: true, clearError: true);

    try {
      final results = await _repository.searchUsersByEmail(query);

      // Filter out excluded users (already on staff)
      final filtered = excludeUserIds != null
          ? results.where((r) => !excludeUserIds.contains(r.id)).toList()
          : results;

      AppLogger.debug('Found ${filtered.length} users matching query', tag: _tag);

      state = state.copyWith(
        results: filtered,
        isSearching: false,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'User search failed for query: $query',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isSearching: false,
        error: appError.userMessage,
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
final staffRepositoryProvider = Provider<IStaffRepository>((ref) {
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
