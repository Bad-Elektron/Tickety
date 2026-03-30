import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../../core/graphics/graphics.dart';
import '../../../core/localization/localization.dart';
import '../../../core/providers/providers.dart';
import '../../../core/state/state.dart';
import '../../../shared/widgets/verified_badge.dart';
import '../../auth/auth.dart';
import '../../notifications/notifications.dart';
import '../../settings/settings.dart';
import '../../subscriptions/subscriptions.dart';
import '../../analytics/analytics.dart';
import '../../referral/referral.dart';
import '../../merch/merch.dart';
import '../../wallet/presentation/transactions_screen.dart';
import '../widgets/widgets.dart';
import 'verification_screen.dart';

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
    ref.watch(localeProvider);
    // Watch auth state - auto rebuilds when auth changes
    final authState = ref.watch(authProvider);

    final isSignedIn = authState.isAuthenticated;

    return Scaffold(
      appBar: AppBar(
        title: Text(L.tr('common_profile')),
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
            if (isSignedIn) ...[
              ProfileSectionHeader(title: L.tr('profile_account')),
              ProfileMenuCard(
                children: [
                  ProfileMenuItem(
                    icon: Icons.settings_outlined,
                    title: L.tr('common_settings'),
                    subtitle: L.tr('settings_app_preferences'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  ProfileMenuItem(
                    icon: Icons.card_giftcard_outlined,
                    title: L.tr('profile_referral'),
                    subtitle: L.tr('profile_referral_sub'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReferralScreen(),
                        ),
                      );
                    },
                  ),
                  ProfileMenuItem(
                    icon: Icons.verified_user_outlined,
                    title: L.tr('identity_verification'),
                    subtitle: L.tr('why_verify_description'),
                    trailing: const _VerificationStatusIndicator(),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const VerificationScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              ProfileSectionHeader(title: L.tr('common_payments')),
              ProfileMenuCard(
                children: [
                  ProfileMenuItem(
                    icon: _appState.tier.icon,
                    title: L.tr('profile_subscription'),
                    subtitle: '${_appState.tier.label} Plan',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionScreen(),
                        ),
                      );
                    },
                  ),
                  ProfileMenuItem(
                    icon: Icons.history_outlined,
                    title: L.tr('profile_transactions'),
                    subtitle: L.tr('purchase_confirmations_receipts'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TransactionsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
            ProfileSectionHeader(title: L.tr('profile_support')),
            ProfileMenuCard(
              children: [
                ProfileMenuItem(
                  icon: Icons.help_outline,
                  title: L.tr('profile_help'),
                  subtitle: L.tr('profile_help_subtitle'),
                ),
                if (isSignedIn)
                  ProfileMenuItem(
                    icon: Icons.chat_bubble_outline,
                    title: L.tr('profile_contact'),
                    subtitle: L.tr('profile_contact_subtitle'),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            _LogoutButton(authState: authState),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

/// Shows verification status indicator on the profile menu item.
class _VerificationStatusIndicator extends ConsumerWidget {
  const _VerificationStatusIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    if (!authState.isAuthenticated) return const SizedBox.shrink();

    // We'll use a FutureBuilder to fetch the status
    return FutureBuilder<String>(
      future: _fetchVerificationStatus(),
      builder: (context, snapshot) {
        final status = snapshot.data ?? 'none';
        return switch (status) {
          'verified' => const VerifiedBadge(size: 18),
          'pending' => const Icon(Icons.hourglass_top, size: 16, color: Colors.amber),
          'failed' => Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }

  Future<String> _fetchVerificationStatus() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return 'none';
      final response = await Supabase.instance.client
          .from('profiles')
          .select('identity_verification_status')
          .eq('id', userId)
          .single();
      return response['identity_verification_status'] as String? ?? 'none';
    } catch (_) {
      return 'none';
    }
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
        tier.icon,
        size: 14,
        color: Colors.white,
      ),
    );
  }
}

class _ProfileHeader extends ConsumerStatefulWidget {
  const _ProfileHeader({
    required this.authState,
    required this.tier,
  });

  final AuthState authState;
  final AccountTier tier;

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  bool _uploading = false;

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;

    setState(() => _uploading = true);

    try {
      final bytes = await image.readAsBytes();
      final ext = image.name.split('.').last;
      final userId = widget.authState.userId!;
      final path = '$userId/avatar.$ext';

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));

      final url = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(path);

      // Bust cache by appending timestamp
      final cachedUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': cachedUrl})
          .eq('id', userId);

      ref.read(authProvider.notifier).setAvatarUrl(cachedUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Avatar updated'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = NoisePresets.vibrantEvents(42);
    final theme = Theme.of(context);
    final isAuthenticated = widget.authState.isAuthenticated;
    final avatarUrl = ref.watch(authProvider).avatarUrl;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          GestureDetector(
            onTap: isAuthenticated && !_uploading ? _pickAndUploadAvatar : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: avatarUrl == null
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: config.colors,
                          )
                        : null,
                    image: avatarUrl != null
                        ? DecorationImage(
                            image: NetworkImage(avatarUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: config.colors.first.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _uploading
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : avatarUrl == null
                          ? Icon(
                              Icons.person_outline,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: 48,
                            )
                          : null,
                ),
                // Camera edit badge
                if (isAuthenticated)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                // Tier badge
                Positioned(
                  top: -4,
                  right: -4,
                  child: _TierBadge(tier: widget.tier),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isAuthenticated
                ? (widget.authState.displayName ?? 'User')
                : L.tr('profile_guest'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (isAuthenticated && widget.authState.handle != null) ...[
            const SizedBox(height: 2),
            Text(
              widget.authState.handle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            isAuthenticated
                ? (widget.authState.email ?? '')
                : L.tr('profile_sign_in_to_access'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!isAuthenticated) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              icon: const Icon(Icons.login, size: 18),
              label: Text(L.tr('common_sign_in')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
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
                    SnackBar(
                      content: Text(L.tr('profile_logout_success')),
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
        label: Text(L.tr('common_sign_out')),
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
