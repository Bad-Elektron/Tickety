import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/providers.dart';
import '../../../core/state/app_state.dart';
import '../models/referral_info.dart';


/// Screen displaying the user's referral code, channel stats, and withdrawal.
class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(referralProvider.notifier).load();
    });
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L.tr('referral_code_copied')),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareCode(String code) {
    Share.share(
      'Join Tickety with my referral code $code and get 50% off your subscription for 6 months! '
      'https://tickety.app/r/$code',
    );
  }

  Future<void> _handleWithdraw() async {
    final info = ref.read(referralProvider).info;
    if (info == null || !info.canWithdraw) return;

    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.tr('referral_withdraw')),
        content: Text(
          'Withdraw ${info.formattedWithdrawable} to your bank account?\n\n'
          'If you haven\'t set up your payout account yet, '
          'you\'ll be directed to complete setup first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L.tr('referral_withdraw')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result =
        await ref.read(referralProvider.notifier).withdrawEarnings();

    if (result == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ref.read(referralProvider).error ??
              'Failed to withdraw. Please try again.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: theme.colorScheme.error,
        ),
      );
      return;
    }

    if (result['needs_onboarding'] == true) {
      final url = result['onboarding_url'] as String?;
      if (url != null) {
        messenger.showSnackBar(
          const SnackBar(
            content:
                Text('Opening Stripe to complete your payout account setup...'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } else if (result['success'] == true) {
      final amountCents = result['amount_cents'] as int? ?? 0;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Withdrawal of \$${(amountCents / 100).toStringAsFixed(2)} initiated!',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(referralProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(L.tr('referral_title')),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: state.isLoading
                ? null
                : () => ref.read(referralProvider.notifier).refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(referralProvider.notifier).refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Loading state
              if (state.isLoading && state.info == null)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.error != null && state.info == null)
                _ErrorView(
                  message: state.error!,
                  onRetry: () => ref.read(referralProvider.notifier).load(),
                )
              else if (state.info != null) ...[
                // Referred user benefit banner (only show on Base tier)
                if (state.info!.wasReferred &&
                    state.info!.hasUnusedSubscriptionBenefit &&
                    ref.watch(subscriptionProvider).effectiveTier == AccountTier.base)
                  _SubscriptionBenefitBanner(),

                // Referral code card
                _ReferralCodeCard(
                  code: state.info!.referralCode,
                  onCopy: () => _copyCode(state.info!.referralCode),
                  onShare: () => _shareCode(state.info!.referralCode),
                ),

                const SizedBox(height: 24),

                // Stats section
                Text(
                  L.tr('referral_stats'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: L.tr('referral_referrals'),
                        value: state.info!.totalReferrals.toString(),
                        icon: Icons.people_outline,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: L.tr('referral_earned'),
                        value: state.info!.formattedTotalEarnings,
                        icon: Icons.payments_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: L.tr('referral_pending'),
                        value: state.info!.formattedPendingEarnings,
                        icon: Icons.schedule_outlined,
                      ),
                    ),
                  ],
                ),

                // Withdrawal section
                if (state.info!.hasEarnings) ...[
                  const SizedBox(height: 16),
                  _WithdrawalCard(
                    info: state.info!,
                    isWithdrawing: state.isWithdrawing,
                    onWithdraw: _handleWithdraw,
                  ),
                ],

                // Channel breakdown
                if (state.info!.channelStats.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _ChannelBreakdown(stats: state.info!.channelStats),
                ],

                // Referred user discount banner
                if (state.info!.wasReferred) ...[
                  const SizedBox(height: 24),
                  _ReferredBanner(info: state.info!),
                ],

                const SizedBox(height: 32),

                // How it works
                Text(
                  L.tr('referral_how_it_works'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _HowItWorksCard(
                  step: '1',
                  title: 'Share Your Code',
                  description:
                      'Select a channel and share your referral link on social media, email, or your website.',
                ),
                const SizedBox(height: 8),
                _HowItWorksCard(
                  step: '2',
                  title: 'Friend Signs Up',
                  description:
                      'They get 50% off Pro or Enterprise for 6 months + discounted platform fees for a year.',
                ),
                const SizedBox(height: 8),
                _HowItWorksCard(
                  step: '3',
                  title: 'You Earn Commission',
                  description:
                      'Earn 10% of platform fees from every purchase your referrals make. Withdraw anytime after 7 days.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionBenefitBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.withValues(alpha: 0.15),
            Colors.orange.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard, color: Colors.amber, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '50% Off for 6 Months!',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You were referred! Upgrade and your discount will be applied automatically.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

class _ReferralCodeCard extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _ReferralCodeCard({
    required this.code,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.primary.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            L.tr('referral_code_label'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onCopy,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    code,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.copy,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.share, size: 18),
            label: Text(L.tr('referral_share_link')),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _WithdrawalCard extends StatelessWidget {
  final ReferralInfo info;
  final bool isWithdrawing;
  final VoidCallback onWithdraw;

  const _WithdrawalCard({
    required this.info,
    required this.isWithdrawing,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: info.canWithdraw
            ? Border.all(color: Colors.green.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available to Withdraw',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      info.formattedWithdrawable,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: info.canWithdraw
                            ? Colors.green
                            : colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (info.paidEarningsCents > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total Paid',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      info.formattedPaidEarnings,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (!info.canWithdraw && info.pendingEarningsCents > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Earnings are available for withdrawal after a 7-day hold period.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (info.canWithdraw) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isWithdrawing ? null : onWithdraw,
                icon: isWithdrawing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_balance, size: 18),
                label: Text(isWithdrawing
                    ? 'Processing...'
                    : 'Withdraw ${info.formattedWithdrawable}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChannelBreakdown extends StatelessWidget {
  final List<ChannelStat> stats;

  const _ChannelBreakdown({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L.tr('referral_channel_performance'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...stats.map((stat) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      stat.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MiniStat(
                            label: L.tr('referral_clicks'), value: stat.clicks.toString()),
                        _MiniStat(
                            label: L.tr('referral_signups'), value: stat.signups.toString()),
                        _MiniStat(
                            label: L.tr('referral_sales'), value: stat.purchases.toString()),
                        _MiniStat(
                            label: L.tr('referral_earned'), value: stat.formattedEarnings),
                      ],
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferredBanner extends StatelessWidget {
  final ReferralInfo info;

  const _ReferredBanner({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isActive = info.isDiscountActive;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.withValues(alpha: 0.1)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? Colors.green.withValues(alpha: 0.3)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.timer_off,
            color: isActive ? Colors.green : colorScheme.onSurfaceVariant,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive
                      ? 'Referral Discount Active'
                      : 'Referral Discount Expired',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color:
                        isActive ? Colors.green : colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  isActive
                      ? '${info.discountDaysRemaining} days remaining — 5% off platform fees'
                      : 'Your referral discount period has ended',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

class _HowItWorksCard extends StatelessWidget {
  final String step;
  final String title;
  final String description;

  const _HowItWorksCard({
    required this.step,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(L.tr('common_retry')),
          ),
        ],
      ),
    );
  }
}
