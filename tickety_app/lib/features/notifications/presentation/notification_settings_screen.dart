import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/notification_preferences_provider.dart';

/// Screen for managing notification preferences.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsState = ref.watch(notificationPreferencesProvider);
    final notifier = ref.read(notificationPreferencesProvider.notifier);
    final prefs = prefsState.preferences;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: true,
      ),
      body: prefsState.isLoading && prefs == null
          ? const Center(child: CircularProgressIndicator())
          : prefs == null
              ? _ErrorView(
                  message: prefsState.error ?? 'Unable to load preferences',
                  onRetry: () => notifier.load(),
                )
              : ListView(
                  children: [
                    // Channels
                    const _SectionHeader(title: 'Channels'),
                    _SettingsCard(
                      children: [
                        _SettingsTile(
                          icon: Icons.notifications_active_outlined,
                          title: 'Push Notifications',
                          subtitle: 'Receive alerts on your device',
                          trailing: Switch.adaptive(
                            value: prefs.pushEnabled,
                            onChanged: (value) => notifier.updatePreference(
                              (p) => p.copyWith(pushEnabled: value),
                            ),
                          ),
                        ),
                        _SettingsTile(
                          icon: Icons.email_outlined,
                          title: 'Email Notifications',
                          subtitle: 'Receive alerts via email',
                          trailing: Switch.adaptive(
                            value: prefs.emailEnabled,
                            onChanged: (value) => notifier.updatePreference(
                              (p) => p.copyWith(emailEnabled: value),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Activity
                    const _SectionHeader(title: 'Activity'),
                    _SettingsCard(
                      dimmed: !prefs.pushEnabled && !prefs.emailEnabled,
                      children: [
                        _SettingsTile(
                          icon: Icons.badge_outlined,
                          title: 'Staff Role Assignments',
                          subtitle: 'When added as usher, seller, or manager',
                          dimmed: !prefs.pushEnabled && !prefs.emailEnabled,
                          trailing: Switch.adaptive(
                            value: prefs.staffAdded,
                            onChanged: (value) => notifier.updatePreference(
                              (p) => p.copyWith(staffAdded: value),
                            ),
                          ),
                        ),
                        _SettingsTile(
                          icon: Icons.confirmation_num_outlined,
                          title: 'Ticket Purchases',
                          subtitle: 'Purchase confirmations and receipts',
                          dimmed: !prefs.pushEnabled && !prefs.emailEnabled,
                          trailing: Switch.adaptive(
                            value: prefs.ticketPurchased,
                            onChanged: (value) => notifier.updatePreference(
                              (p) => p.copyWith(ticketPurchased: value),
                            ),
                          ),
                        ),
                        _SettingsTile(
                          icon: Icons.qr_code_scanner_outlined,
                          title: 'Ticket Scanned',
                          subtitle: 'When your ticket is used at an event',
                          dimmed: !prefs.pushEnabled && !prefs.emailEnabled,
                          trailing: Switch.adaptive(
                            value: prefs.ticketUsed,
                            onChanged: (value) => notifier.updatePreference(
                              (p) => p.copyWith(ticketUsed: value),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Events
                    const _SectionHeader(title: 'Events'),
                    _SettingsCard(
                      dimmed: !prefs.pushEnabled && !prefs.emailEnabled,
                      children: [
                        _SettingsTile(
                          icon: Icons.alarm_outlined,
                          title: 'Event Reminders',
                          subtitle: 'Reminders before events you\'re attending',
                          dimmed: !prefs.pushEnabled && !prefs.emailEnabled,
                          trailing: Switch.adaptive(
                            value: prefs.eventReminders,
                            onChanged: (value) => notifier.updatePreference(
                              (p) => p.copyWith(eventReminders: value),
                            ),
                          ),
                        ),
                        _SettingsTile(
                          icon: Icons.update_outlined,
                          title: 'Event Updates',
                          subtitle: 'Changes to events you have tickets for',
                          dimmed: !prefs.pushEnabled && !prefs.emailEnabled,
                          trailing: Switch.adaptive(
                            value: prefs.eventUpdates,
                            onChanged: (value) => notifier.updatePreference(
                              (p) => p.copyWith(eventUpdates: value),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Promotional
                    const _SectionHeader(title: 'Promotional'),
                    _SettingsCard(
                      dimmed: !prefs.pushEnabled && !prefs.emailEnabled,
                      children: [
                        _SettingsTile(
                          icon: Icons.campaign_outlined,
                          title: 'Marketing',
                          subtitle: 'Promotional content and special offers',
                          dimmed: !prefs.pushEnabled && !prefs.emailEnabled,
                          trailing: Switch.adaptive(
                            value: prefs.marketing,
                            onChanged: (value) => notifier.updatePreference(
                              (p) => p.copyWith(marketing: value),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children, this.dimmed = false});

  final List<Widget> children;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedOpacity(
      opacity: dimmed ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(
                  height: 1,
                  indent: 56,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.dimmed = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
