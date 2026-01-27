import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/notification_model.dart';
import 'i_notification_repository.dart';

export 'i_notification_repository.dart' show INotificationRepository;

const _tag = 'NotificationRepository';

/// Supabase implementation of [INotificationRepository].
///
/// Uses Supabase Realtime for live notification updates.
class NotificationRepository implements INotificationRepository {
  final _client = SupabaseService.instance.client;
  RealtimeChannel? _channel;
  final _notificationsController = StreamController<List<NotificationModel>>.broadcast();

  /// Initialize the repository and set up realtime subscription.
  NotificationRepository() {
    _setupRealtimeSubscription();
  }

  void _setupRealtimeSubscription() {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.debug('No user logged in, skipping realtime subscription', tag: _tag);
      return;
    }

    AppLogger.debug('Setting up realtime subscription for notifications', tag: _tag);

    _channel = _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            AppLogger.debug('Realtime notification received: ${payload.newRecord}', tag: _tag);
            // Fetch fresh data when a new notification arrives
            _fetchAndEmitNotifications();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            AppLogger.debug('Notification updated: ${payload.newRecord}', tag: _tag);
            _fetchAndEmitNotifications();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            AppLogger.debug('Notification deleted', tag: _tag);
            _fetchAndEmitNotifications();
          },
        )
        .subscribe((status, [error]) {
          AppLogger.debug('Realtime subscription status: $status', tag: _tag);
          if (error != null) {
            AppLogger.error('Realtime subscription error', error: error, tag: _tag);
          }
        });
  }

  Future<void> _fetchAndEmitNotifications() async {
    try {
      final notifications = await getNotifications();
      _notificationsController.add(notifications);
    } catch (e, s) {
      AppLogger.error('Failed to fetch notifications after realtime update', error: e, stackTrace: s, tag: _tag);
    }
  }

  @override
  Stream<List<NotificationModel>> watchNotifications() {
    // Immediately fetch and emit current notifications
    _fetchAndEmitNotifications();
    return _notificationsController.stream;
  }

  @override
  Future<List<NotificationModel>> getNotifications() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.debug('No user logged in, returning empty notifications', tag: _tag);
      return [];
    }

    AppLogger.debug('Fetching notifications for user: $userId', tag: _tag);

    try {
      final response = await _client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      final notifications = (response as List<dynamic>)
          .map((json) => NotificationModel.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.debug('Fetched ${notifications.length} notifications', tag: _tag);
      return notifications;
    } catch (e, s) {
      AppLogger.error('Failed to fetch notifications', error: e, stackTrace: s, tag: _tag);
      rethrow;
    }
  }

  @override
  Future<int> getUnreadCount() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return 0;

    AppLogger.debug('Getting unread count for user: $userId', tag: _tag);

    try {
      final response = await _client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('read', false);

      final count = (response as List<dynamic>).length;
      AppLogger.debug('Unread count: $count', tag: _tag);
      return count;
    } catch (e, s) {
      AppLogger.error('Failed to get unread count', error: e, stackTrace: s, tag: _tag);
      return 0;
    }
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    AppLogger.debug('Marking notification as read: $notificationId', tag: _tag);

    try {
      await _client
          .from('notifications')
          .update({'read': true})
          .eq('id', notificationId);

      AppLogger.info('Notification marked as read: $notificationId', tag: _tag);
    } catch (e, s) {
      AppLogger.error('Failed to mark notification as read', error: e, stackTrace: s, tag: _tag);
      rethrow;
    }
  }

  @override
  Future<void> markAllAsRead() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return;

    AppLogger.debug('Marking all notifications as read for user: $userId', tag: _tag);

    try {
      await _client
          .from('notifications')
          .update({'read': true})
          .eq('user_id', userId)
          .eq('read', false);

      AppLogger.info('All notifications marked as read', tag: _tag);
    } catch (e, s) {
      AppLogger.error('Failed to mark all notifications as read', error: e, stackTrace: s, tag: _tag);
      rethrow;
    }
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    AppLogger.debug('Deleting notification: $notificationId', tag: _tag);

    try {
      await _client
          .from('notifications')
          .delete()
          .eq('id', notificationId);

      AppLogger.info('Notification deleted: $notificationId', tag: _tag);
    } catch (e, s) {
      AppLogger.error('Failed to delete notification', error: e, stackTrace: s, tag: _tag);
      rethrow;
    }
  }

  @override
  void dispose() {
    AppLogger.debug('Disposing notification repository', tag: _tag);
    _channel?.unsubscribe();
    _notificationsController.close();
  }
}
