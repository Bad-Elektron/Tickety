import '../models/notification_model.dart';

/// Abstract repository interface for notification operations.
///
/// Defines the contract for managing user notifications.
/// Implementations can use different data sources (Supabase, mock, etc).
abstract class INotificationRepository {
  /// Watch notifications stream for realtime updates.
  /// Returns a stream that emits when notifications change.
  Stream<List<NotificationModel>> watchNotifications();

  /// Get all notifications for the current user.
  Future<List<NotificationModel>> getNotifications();

  /// Get unread notification count.
  Future<int> getUnreadCount();

  /// Mark a notification as read.
  Future<void> markAsRead(String notificationId);

  /// Mark all notifications as read.
  Future<void> markAllAsRead();

  /// Delete a notification.
  Future<void> deleteNotification(String notificationId);

  /// Dispose resources (e.g., close streams).
  void dispose();
}
