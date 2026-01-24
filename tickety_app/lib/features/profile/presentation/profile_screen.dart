import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/providers/providers.dart';
// Hide AuthState from state.dart to avoid collision with Riverpod's AuthState
import '../../../core/state/state.dart' hide AuthState;
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
            const ProfileSectionHeader(title: 'Developer'),
            _DeveloperSection(appState: _appState),
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
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Debug Mode Toggle
              Row(
                children: [
                  Icon(
                    Icons.bug_report_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Debug Mode',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Shows FPS overlay',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: appState.debugMode,
                    onChanged: (value) => appState.debugMode = value,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              // Account Tier Selector
              Row(
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account Tier',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Simulated tier level',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Three-way tier toggle
              _TierToggle(appState: appState),
            ],
          ),
        ),
      ),
    );
  }
}

class _TierToggle extends StatelessWidget {
  const _TierToggle({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: AccountTier.values.map((tier) {
          final isSelected = appState.tier == tier;
          final tierColor = Color(tier.color);

          return Expanded(
            child: GestureDetector(
              onTap: () => appState.tier = tier,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? tierColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: tierColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      _getTierIcon(tier),
                      size: 20,
                      color: isSelected
                          ? Colors.white
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tier.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _getTierIcon(AccountTier tier) {
    switch (tier) {
      case AccountTier.base:
        return Icons.person_outline;
      case AccountTier.pro:
        return Icons.star_outline;
      case AccountTier.enterprise:
        return Icons.diamond_outlined;
    }
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
