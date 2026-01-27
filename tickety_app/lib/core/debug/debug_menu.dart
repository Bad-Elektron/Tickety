import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/payments/payments.dart';
import '../providers/notification_provider.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';

/// Global navigator key for accessing navigator from anywhere.
/// Used by DebugFab which exists outside the Navigator tree.
final GlobalKey<NavigatorState> debugNavigatorKey = GlobalKey<NavigatorState>();

/// Debug menu item configuration.
class DebugMenuItem {
  final String title;
  final IconData icon;
  final Widget Function(BuildContext context) builder;
  final Color? color;

  const DebugMenuItem({
    required this.title,
    required this.icon,
    required this.builder,
    this.color,
  });
}

/// Debug menu that provides quick access to test screens.
///
/// Only available in debug builds (kDebugMode).
class DebugMenu extends ConsumerWidget {
  const DebugMenu({super.key});

  static final List<DebugMenuItem> _menuItems = [
    DebugMenuItem(
      title: 'Payment Testing',
      icon: Icons.payment,
      color: Colors.green,
      builder: (_) => const PaymentTestScreen(),
    ),
    // Add more test screens here as needed
  ];

  /// Shows the debug menu as a bottom sheet.
  static void show(BuildContext context) {
    if (!kDebugMode) return;

    // Use the navigator key's context if available (for DebugFab outside Navigator tree)
    // Otherwise fall back to provided context (for calls from within Navigator tree)
    final navContext = debugNavigatorKey.currentContext ?? context;

    showModalBottomSheet(
      context: navContext,
      backgroundColor: Colors.transparent,
      builder: (context) => const DebugMenu(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.bug_report,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Debug Menu',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Development tools and test screens',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          // Menu items
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ..._menuItems.map((item) => _DebugMenuTile(item: item)),
                const Divider(height: 24),
                // Notification testing
                _NotificationTestSection(ref: ref),
                const Divider(height: 24),
                // Quick toggles
                _DebugToggleRow(),
              ],
            ),
          ),

          // Warning footer
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Debug features are only available in development builds',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugMenuTile extends StatelessWidget {
  final DebugMenuItem item;

  const _DebugMenuTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.color ?? theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(builder: item.builder),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DebugToggleRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appState = AppState();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Toggles',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _QuickToggle(
                label: 'FPS Overlay',
                icon: Icons.speed,
                value: appState.debugMode,
                onChanged: (_) => appState.toggleDebugMode(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickToggle(
                label: 'Tier: ${appState.tier.label}',
                icon: Icons.star,
                value: appState.tier != AccountTier.base,
                onChanged: (_) => appState.cycleTier(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _QuickToggle({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      value ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section for testing notifications in the debug menu.
class _NotificationTestSection extends StatelessWidget {
  final WidgetRef ref;

  const _NotificationTestSection({required this.ref});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notificationState = ref.watch(notificationProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notification Testing',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        // Status info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    NotificationService.isSupported
                        ? Icons.check_circle
                        : Icons.cancel,
                    size: 16,
                    color: NotificationService.isSupported
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Platform supported: ${NotificationService.isSupported ? 'Yes' : 'No'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Unread: ${notificationState.unreadCount}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Total: ${notificationState.notifications.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Test button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              ref.read(notificationProvider.notifier).sendTestNotification();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Test notification sent!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.notifications_active, size: 18),
            label: const Text('Send Test Notification'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Request permissions button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: NotificationService.isSupported
                ? () async {
                    final granted = await NotificationService.instance.requestPermissions();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            granted
                                ? 'Notification permissions granted!'
                                : 'Notification permissions denied',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                : null,
            icon: const Icon(Icons.security, size: 18),
            label: const Text('Request Permissions'),
          ),
        ),
      ],
    );
  }
}

/// Floating debug button that appears in debug mode.
///
/// Shows a small bug icon that opens the debug menu when tapped.
class DebugFab extends StatelessWidget {
  const DebugFab({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return Positioned(
      right: 16,
      bottom: 80,
      child: FloatingActionButton.small(
        heroTag: 'debug_fab',
        backgroundColor: Colors.orange,
        onPressed: () => DebugMenu.show(context),
        child: const Icon(Icons.bug_report, color: Colors.white),
      ),
    );
  }
}
