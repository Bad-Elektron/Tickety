import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/errors.dart';
import '../services/services.dart';
import '../../features/notifications/models/notification_preferences.dart';

const _tag = 'NotificationPreferencesProvider';

/// State for notification preferences.
class NotificationPreferencesState {
  final NotificationPreferences? preferences;
  final bool isLoading;
  final String? error;

  const NotificationPreferencesState({
    this.preferences,
    this.isLoading = false,
    this.error,
  });

  NotificationPreferencesState copyWith({
    NotificationPreferences? preferences,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return NotificationPreferencesState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier that manages notification preferences with Supabase persistence.
class NotificationPreferencesNotifier
    extends StateNotifier<NotificationPreferencesState> {
  NotificationPreferencesNotifier()
      : super(const NotificationPreferencesState()) {
    _listenToAuthChanges();
    _init();
  }

  StreamSubscription<dynamic>? _authSubscription;
  String? _currentUserId;

  void _listenToAuthChanges() {
    _authSubscription =
        SupabaseService.instance.client.auth.onAuthStateChange.listen((data) {
      final newUserId = data.session?.user.id;

      if (newUserId != _currentUserId) {
        if (newUserId != null && _currentUserId == null) {
          _currentUserId = newUserId;
          load();
        } else if (newUserId == null && _currentUserId != null) {
          _currentUserId = null;
          state = const NotificationPreferencesState();
        }
      }
    });
  }

  void _init() {
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;
    _currentUserId = user.id;
    load();
  }

  /// Load preferences from Supabase, upserting defaults if none exist.
  Future<void> load() async {
    final userId = _currentUserId;
    if (userId == null) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final client = SupabaseService.instance.client;

      // Upsert default row — no-ops if row already exists
      await client.from('notification_preferences').upsert(
        NotificationPreferences.defaults(userId).toJson(),
        onConflict: 'user_id',
        ignoreDuplicates: true,
      );

      final response = await client
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .single();

      final prefs = NotificationPreferences.fromJson(response);

      state = state.copyWith(
        preferences: prefs,
        isLoading: false,
      );

      AppLogger.debug('Loaded notification preferences', tag: _tag);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load notification preferences',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
    }
  }

  /// Update a single preference field with optimistic local update.
  Future<void> updatePreference(
    NotificationPreferences Function(NotificationPreferences) updater,
  ) async {
    final current = state.preferences;
    if (current == null) return;

    final updated = updater(current);

    // Optimistic update
    state = state.copyWith(preferences: updated);

    try {
      await SupabaseService.instance.client
          .from('notification_preferences')
          .update(updated.toJson())
          .eq('user_id', updated.userId);

      AppLogger.debug('Updated notification preferences', tag: _tag);
    } catch (e, s) {
      // Revert on failure
      AppLogger.error(
        'Failed to update notification preferences',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        preferences: current,
        error: 'Failed to save preference',
      );
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

/// Global notification preferences provider.
final notificationPreferencesProvider = StateNotifierProvider<
    NotificationPreferencesNotifier, NotificationPreferencesState>((ref) {
  return NotificationPreferencesNotifier();
});
