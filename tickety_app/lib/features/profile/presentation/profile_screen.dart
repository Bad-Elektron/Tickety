import 'package:flutter/material.dart';

import '../../../core/graphics/graphics.dart';
import '../widgets/widgets.dart';

/// The profile screen displaying user information and settings.
///
/// Contains placeholder settings organized into sections:
/// Account, Payments, and Support. All menu items provide
/// responsive tap feedback.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileHeader(),
            const ProfileSectionHeader(title: 'Account'),
            ProfileMenuCard(
              children: [
                ProfileMenuItem(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  subtitle: 'App preferences',
                ),
                ProfileMenuItem(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Manage alerts',
                ),
                ProfileMenuItem(
                  icon: Icons.lock_outline,
                  title: 'Privacy',
                  subtitle: 'Data and permissions',
                ),
              ],
            ),
            const ProfileSectionHeader(title: 'Payments'),
            ProfileMenuCard(
              children: [
                ProfileMenuItem(
                  icon: Icons.receipt_long_outlined,
                  title: 'Billing',
                  subtitle: 'Invoices and receipts',
                ),
                ProfileMenuItem(
                  icon: Icons.credit_card_outlined,
                  title: 'Payment Methods',
                  subtitle: 'Cards and wallets',
                ),
                ProfileMenuItem(
                  icon: Icons.history_outlined,
                  title: 'Transactions',
                  subtitle: 'Purchase history',
                ),
              ],
            ),
            const ProfileSectionHeader(title: 'Support'),
            ProfileMenuCard(
              children: [
                ProfileMenuItem(
                  icon: Icons.help_outline,
                  title: 'Help Center',
                  subtitle: 'FAQs and guides',
                ),
                ProfileMenuItem(
                  icon: Icons.chat_bubble_outline,
                  title: 'Contact Us',
                  subtitle: 'Get in touch',
                ),
              ],
            ),
            const SizedBox(height: 32),
            _LogoutButton(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final config = NoisePresets.vibrantEvents(42);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: config.colors,
              ),
              boxShadow: [
                BoxShadow(
                  color: config.colors.first.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.person_outline,
              color: Colors.white.withValues(alpha: 0.9),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Guest User',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'guest@tickety.app',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Coming soon'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit Profile'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: OutlinedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Coming soon'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        icon: const Icon(Icons.logout, size: 20),
        label: const Text('Log Out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
