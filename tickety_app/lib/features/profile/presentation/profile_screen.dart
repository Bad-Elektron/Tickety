import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/debug/debug.dart';
import '../../../core/graphics/graphics.dart';
import '../../../core/providers/providers.dart';
import '../../../core/state/state.dart';
import '../../auth/auth.dart';
import '../../staff/staff.dart';
import '../widgets/widgets.dart';

/// The profile screen displaying user information and settings.
///
/// Uses Riverpod for auth state - no more manual listeners!
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _appState = AppState();

  @override
  void initState() {
    super.initState();
    _appState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _appState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth state - auto rebuilds when auth changes
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileHeader(
              authState: authState,
              tier: _appState.tier,
            ),
            const ProfileSectionHeader(title: 'Account'),
            ProfileMenuCard(
              children: [
                ProfileMenuItem(
                  icon: Icons.badge_outlined,
                  title: 'Staff Dashboard',
                  subtitle: 'Manage events as staff',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StaffDashboardScreen(),
                      ),
                    );
                  },
                ),
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
            if (kDebugMode) ...[
              const ProfileSectionHeader(title: 'Developer'),
              _DeveloperSection(appState: _appState),
            ],
            const SizedBox(height: 32),
            _LogoutButton(authState: authState),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier});

  final AccountTier tier;

  @override
  Widget build(BuildContext context) {
    final tierColor = Color(tier.color);

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: tierColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).scaffoldBackgroundColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: tierColor.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        _getIcon(),
        size: 14,
        color: Colors.white,
      ),
    );
  }

  IconData _getIcon() {
    switch (tier) {
      case AccountTier.base:
        return Icons.person;
      case AccountTier.pro:
        return Icons.star;
      case AccountTier.enterprise:
        return Icons.diamond;
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.authState,
    required this.tier,
  });

  final AuthState authState;
  final AccountTier tier;

  @override
  Widget build(BuildContext context) {
    final config = NoisePresets.vibrantEvents(42);
    final theme = Theme.of(context);
    final isAuthenticated = authState.isAuthenticated;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
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
              // Tier badge
              Positioned(
                top: -4,
                right: -4,
                child: _TierBadge(tier: tier),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isAuthenticated
                ? (authState.displayName ?? 'User')
                : 'Guest User',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isAuthenticated
                ? (authState.email ?? '')
                : 'Sign in to access all features',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (isAuthenticated)
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
            )
          else
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Sign In'),
              style: FilledButton.styleFrom(
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

class _DeveloperSection extends StatelessWidget {
  const _DeveloperSection({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    // Only show in debug builds
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        color: Colors.orange.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.orange.withValues(alpha: 0.3),
          ),
        ),
        child: InkWell(
          onTap: () => DebugMenu.show(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.bug_report,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Debug Menu',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'FPS overlay, test screens, dev tools',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Quick status indicators
                      Row(
                        children: [
                          _StatusChip(
                            label: 'FPS ${appState.debugMode ? "ON" : "OFF"}',
                            isActive: appState.debugMode,
                          ),
                          const SizedBox(width: 8),
                          _StatusChip(
                            label: appState.tier.label,
                            isActive: appState.tier != AccountTier.base,
                            color: Color(appState.tier.color),
                          ),
                        ],
                      ),
                    ],
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.isActive,
    this.color,
  });

  final String label;
  final bool isActive;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? (isActive ? Colors.green : Colors.grey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: chipColor,
        ),
      ),
    );
  }
}

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Don't show logout button if not authenticated
    if (!authState.isAuthenticated) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: OutlinedButton.icon(
        onPressed: authState.isLoading
            ? null
            : () async {
                await ref.read(authProvider.notifier).signOut();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Signed out successfully'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
        icon: authState.isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.logout, size: 20),
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
