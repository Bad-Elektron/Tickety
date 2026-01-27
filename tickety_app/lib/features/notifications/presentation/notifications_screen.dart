import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../events/presentation/event_details_screen.dart';
import '../models/notification_model.dart';

/// Screen displaying the user's notifications.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh notifications when screen opens
    Future.microtask(() {
      ref.read(notificationProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(notificationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: true,
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () {
                ref.read(notificationProvider.notifier).markAllAsRead();
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? _buildErrorState(context, state.error!, theme, colorScheme)
              : state.notifications.isEmpty
                  ? _buildEmptyState(context, theme, colorScheme)
                  : RefreshIndicator(
                      onRefresh: () => ref.read(notificationProvider.notifier).refresh(),
                      child: _buildNotificationList(context, state.notifications),
                    ),
    );
  }

  Widget _buildNotificationList(BuildContext context, List<NotificationModel> notifications) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: notifications.length,
      itemBuilder: (context, index) {
        final notification = notifications[index];
        return _NotificationTile(
          notification: notification,
          onTap: () => _handleNotificationTap(notification),
          onDismiss: () {
            ref.read(notificationProvider.notifier).deleteNotification(notification.id);
          },
        );
      },
    );
  }

  void _handleNotificationTap(NotificationModel notification) {
    // Mark as read
    if (!notification.read) {
      ref.read(notificationProvider.notifier).markAsRead(notification.id);
    }

    // Navigate based on notification type
    switch (notification.type) {
      case NotificationType.staffAdded:
        _navigateToEvent(notification.eventId);
        break;
      case NotificationType.ticketPurchased:
      case NotificationType.ticketUsed:
        _navigateToEvent(notification.eventId);
        break;
      case NotificationType.eventReminder:
        _navigateToEvent(notification.eventId);
        break;
      case NotificationType.unknown:
        break;
    }
  }

  void _navigateToEvent(String? eventId) async {
    if (eventId == null) return;

    // Fetch event details and navigate
    final eventsState = ref.read(eventsProvider);
    final event = eventsState.events.where((e) => e.id == eventId).firstOrNull;

    if (event != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EventDetailsScreen(event: event),
        ),
      );
    } else {
      // Event not in cache - refresh events and try again
      await ref.read(eventsProvider.notifier).refresh();
      final refreshedState = ref.read(eventsProvider);
      final refreshedEvent = refreshedState.events.where((e) => e.id == eventId).firstOrNull;

      if (refreshedEvent != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailsScreen(event: refreshedEvent),
          ),
        );
      }
    }
  }

  Widget _buildErrorState(
    BuildContext context,
    String error,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: colorScheme.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load notifications',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => ref.read(notificationProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none,
                size: 48,
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No notifications',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ll be notified when you\'re\nadded as staff to an event.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: colorScheme.error,
        child: Icon(
          Icons.delete,
          color: colorScheme.onError,
        ),
      ),
      child: Material(
        color: notification.read
            ? Colors.transparent
            : colorScheme.primaryContainer.withValues(alpha: 0.15),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _getIconBackgroundColor(colorScheme),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIcon(),
                    size: 22,
                    color: _getIconColor(colorScheme),
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: notification.read ? FontWeight.w500 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(notification.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                // Unread indicator
                if (!notification.read)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8, top: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (notification.type) {
      case NotificationType.staffAdded:
        return Icons.badge_outlined;
      case NotificationType.ticketPurchased:
        return Icons.confirmation_number_outlined;
      case NotificationType.ticketUsed:
        return Icons.check_circle_outline;
      case NotificationType.eventReminder:
        return Icons.event_outlined;
      case NotificationType.unknown:
        return Icons.notifications_outlined;
    }
  }

  Color _getIconBackgroundColor(ColorScheme colorScheme) {
    switch (notification.type) {
      case NotificationType.staffAdded:
        return Colors.blue.withValues(alpha: 0.15);
      case NotificationType.ticketPurchased:
        return Colors.green.withValues(alpha: 0.15);
      case NotificationType.ticketUsed:
        return Colors.purple.withValues(alpha: 0.15);
      case NotificationType.eventReminder:
        return Colors.orange.withValues(alpha: 0.15);
      case NotificationType.unknown:
        return colorScheme.surfaceContainerHighest;
    }
  }

  Color _getIconColor(ColorScheme colorScheme) {
    switch (notification.type) {
      case NotificationType.staffAdded:
        return Colors.blue;
      case NotificationType.ticketPurchased:
        return Colors.green;
      case NotificationType.ticketUsed:
        return Colors.purple;
      case NotificationType.eventReminder:
        return Colors.orange;
      case NotificationType.unknown:
        return colorScheme.onSurfaceVariant;
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inDays < 1) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dateTime.month - 1]} ${dateTime.day}';
    }
  }
}
