import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/providers/providers.dart';
import '../presentation/notifications_screen.dart';

/// A notification bell icon with an unread count badge.
///
/// Shows a red badge with the unread count when there are unread notifications.
/// Tapping navigates to the notifications screen.
class NotificationBadge extends ConsumerWidget {
  const NotificationBadge({
    super.key,
    this.size = 40,
    this.iconSize = 24,
    this.seed = 555,
  });

  final double size;
  final double iconSize;
  final int seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = NoisePresets.darkMood(seed);

    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            // Bell icon button with gradient
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                  );
                },
                customBorder: const CircleBorder(),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: config.colors,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: config.colors.last.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      unreadCount > 0
                          ? Icons.notifications_active
                          : Icons.notifications_outlined,
                      color: const Color(0xE6FFFFFF),
                      size: size * 0.5,
                    ),
                  ),
                ),
              ),
            ),
            // Badge
            if (unreadCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.scaffoldBackgroundColor,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onError,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A compact notification indicator dot.
///
/// Shows a small red dot when there are unread notifications.
/// Useful for space-constrained areas.
class NotificationDot extends ConsumerWidget {
  const NotificationDot({
    super.key,
    this.size = 8,
  });

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUnread = ref.watch(hasUnreadNotificationsProvider);

    if (!hasUnread) {
      return const SizedBox.shrink();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        shape: BoxShape.circle,
      ),
    );
  }
}
