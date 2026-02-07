import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/errors.dart';
import '../services/services.dart';
import '../../features/notifications/data/notification_repository.dart';
import '../../features/notifications/models/notification_model.dart';

const _tag = 'NotificationProvider';

/// State for notification management.
class NotificationState {
  final List<NotificationModel> notifications;
  final int unreadCount;
  final bool isLoading;
  final String? error;

  const NotificationState({
    this.notifications = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.error,
  });

  NotificationState copyWith({
    List<NotificationModel>? notifications,
    int? unreadCount,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier that manages notification state and realtime updates.
class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier() : super(const NotificationState()) {
    _init();
    _listenToAuthChanges();
  }

  NotificationRepository? _repository;
  StreamSubscription<List<NotificationModel>>? _subscription;
  StreamSubscription<dynamic>? _authSubscription;
  bool _permissionsRequested = false;
  String? _currentUserId;

  void _listenToAuthChanges() {
    _authSubscription = SupabaseService.instance.client.auth.onAuthStateChange.listen((data) {
      final newUserId = data.session?.user.id;

      if (newUserId != _currentUserId) {
        AppLogger.debug('Auth state changed: ${newUserId != null ? 'logged in' : 'logged out'}', tag: _tag);

        if (newUserId != null && _currentUserId == null) {
          // User logged in
          _currentUserId = newUserId;
          onUserLoggedIn();
        } else if (newUserId == null && _currentUserId != null) {
          // User logged out
          _currentUserId = null;
          onUserLoggedOut();
        }
      }
    });
  }

  void _init() {
    AppLogger.debug('Initializing notification notifier', tag: _tag);

    // Only set up if user is logged in
    final user = SupabaseService.instance.currentUser;
    if (user == null) {
      AppLogger.debug('No user logged in, skipping notification setup', tag: _tag);
      return;
    }

    _currentUserId = user.id;
    _repository = NotificationRepository();
    _subscribeToNotifications();
    _requestNotificationPermissions();
  }

  void _subscribeToNotifications() {
    AppLogger.debug('Subscribing to notifications stream', tag: _tag);

    _subscription = _repository?.watchNotifications().listen(
      (notifications) {
        AppLogger.debug('Received ${notifications.length} notifications', tag: _tag);

        final unreadCount = notifications.where((n) => !n.read).length;

        // Check for new notifications to show local notification
        if (state.notifications.isNotEmpty && notifications.isNotEmpty) {
          final newNotifications = notifications.where(
            (n) => !state.notifications.any((old) => old.id == n.id),
          );

          for (final notification in newNotifications) {
            _showLocalNotification(notification);
          }
        }

        state = state.copyWith(
          notifications: notifications,
          unreadCount: unreadCount,
          isLoading: false,
          clearError: true,
        );
      },
      onError: (error, stack) {
        AppLogger.error(
          'Notification stream error',
          error: error,
          stackTrace: stack,
          tag: _tag,
        );
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load notifications',
        );
      },
    );
  }

  Future<void> _requestNotificationPermissions() async {
    if (_permissionsRequested) return;
    _permissionsRequested = true;

    if (!NotificationService.isSupported) return;

    try {
      final hasPermission = await NotificationService.instance.hasPermissions();
      if (!hasPermission) {
        await NotificationService.instance.requestPermissions();
      }
    } catch (e, s) {
      AppLogger.error(
        'Failed to request notification permissions',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
    }
  }

  void _showLocalNotification(NotificationModel notification) async {
    if (!NotificationService.isSupported) return;

    try {
      await NotificationService.instance.showNotification(
        id: notification.id.hashCode,
        title: notification.title,
        body: notification.body,
        payload: notification.id,
      );
      AppLogger.debug('Showed local notification: ${notification.title}', tag: _tag);
    } catch (e, s) {
      AppLogger.error(
        'Failed to show local notification',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
    }
  }

  /// Refresh notifications from the server.
  Future<void> refresh() async {
    AppLogger.debug('Refreshing notifications', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final notifications = await _repository?.getNotifications() ?? [];
      final unreadCount = notifications.where((n) => !n.read).length;

      state = state.copyWith(
        notifications: notifications,
        unreadCount: unreadCount,
        isLoading: false,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error('Failed to refresh notifications', error: e, stackTrace: s, tag: _tag);
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
    }
  }

  /// Mark a notification as read.
  Future<void> markAsRead(String notificationId) async {
    AppLogger.debug('Marking notification as read: $notificationId', tag: _tag);

    try {
      await _repository?.markAsRead(notificationId);

      // Update local state immediately for responsiveness
      final updatedNotifications = state.notifications.map((n) {
        if (n.id == notificationId) {
          return n.copyWith(read: true);
        }
        return n;
      }).toList();

      final unreadCount = updatedNotifications.where((n) => !n.read).length;

      state = state.copyWith(
        notifications: updatedNotifications,
        unreadCount: unreadCount,
      );
    } catch (e, s) {
      AppLogger.error('Failed to mark notification as read', error: e, stackTrace: s, tag: _tag);
    }
  }

  /// Mark all notifications as read.
  Future<void> markAllAsRead() async {
    AppLogger.debug('Marking all notifications as read', tag: _tag);

    try {
      await _repository?.markAllAsRead();

      // Update local state immediately
      final updatedNotifications = state.notifications.map(
        (n) => n.copyWith(read: true),
      ).toList();

      state = state.copyWith(
        notifications: updatedNotifications,
        unreadCount: 0,
      );
    } catch (e, s) {
      AppLogger.error('Failed to mark all notifications as read', error: e, stackTrace: s, tag: _tag);
    }
  }

  /// Delete a notification.
  Future<void> deleteNotification(String notificationId) async {
    AppLogger.debug('Deleting notification: $notificationId', tag: _tag);

    try {
      await _repository?.deleteNotification(notificationId);

      // Update local state immediately
      final updatedNotifications = state.notifications
          .where((n) => n.id != notificationId)
          .toList();

      final unreadCount = updatedNotifications.where((n) => !n.read).length;

      state = state.copyWith(
        notifications: updatedNotifications,
        unreadCount: unreadCount,
      );
    } catch (e, s) {
      AppLogger.error('Failed to delete notification', error: e, stackTrace: s, tag: _tag);
    }
  }

  /// Clear all notifications.
  Future<void> clearAll() async {
    AppLogger.debug('Clearing all notifications', tag: _tag);

    try {
      await _repository?.clearAll();

      state = state.copyWith(
        notifications: [],
        unreadCount: 0,
      );
    } catch (e, s) {
      AppLogger.error('Failed to clear all notifications', error: e, stackTrace: s, tag: _tag);
    }
  }

  /// Re-initialize when user logs in.
  void onUserLoggedIn() {
    AppLogger.debug('User logged in, initializing notifications', tag: _tag);
    _cleanupNotificationResources();

    _repository = NotificationRepository();
    _subscribeToNotifications();
    _requestNotificationPermissions();
  }

  /// Clean up when user logs out.
  void onUserLoggedOut() {
    AppLogger.debug('User logged out, cleaning up notifications', tag: _tag);
    _cleanupNotificationResources();
    state = const NotificationState();
  }

  /// Send a test notification (debug only).
  /// This creates a fake notification and shows it via local notifications.
  Future<void> sendTestNotification() async {
    AppLogger.info('Sending test notification', tag: _tag);

    final testNotification = NotificationModel(
      id: 'test_${DateTime.now().millisecondsSinceEpoch}',
      userId: SupabaseService.instance.currentUser?.id ?? 'test_user',
      type: NotificationType.staffAdded,
      title: 'Test Notification',
      body: 'You have been added as a Manager for "Summer Music Festival"',
      data: {
        'event_id': 'evt_001',
        'event_title': 'Summer Music Festival',
        'role': 'manager',
      },
      read: false,
      createdAt: DateTime.now(),
    );

    // Add to local state
    final updatedNotifications = [testNotification, ...state.notifications];
    state = state.copyWith(
      notifications: updatedNotifications,
      unreadCount: state.unreadCount + 1,
    );

    // Show local notification
    _showLocalNotification(testNotification);
  }

  void _cleanupNotificationResources() {
    _subscription?.cancel();
    _subscription = null;
    _repository?.dispose();
    _repository = null;
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _cleanupNotificationResources();
    super.dispose();
  }
}

/// Global notification provider.
final notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier();
});

/// Convenience provider for unread notification count.
final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationProvider).unreadCount;
});

/// Convenience provider for checking if there are unread notifications.
final hasUnreadNotificationsProvider = Provider<bool>((ref) {
  return ref.watch(unreadNotificationCountProvider) > 0;
});
