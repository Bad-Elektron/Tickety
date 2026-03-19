import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/referral_provider.dart';
import '../../../core/providers/subscription_provider.dart';
import '../../../core/services/services.dart';
import '../../../core/state/app_state.dart';
import '../models/tier_benefits.dart';
import '../widgets/tier_card.dart';

/// Screen for managing user subscription.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  AccountTier? _upgradingTier;

  @override
  Widget build(BuildContext context) {
    final subscriptionState = ref.watch(subscriptionProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(L.tr('subscription_title')),
        centerTitle: true,
      ),
      body: subscriptionState.isLoading && subscriptionState.subscription == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(subscriptionProvider.notifier).load(),
              child: ListView(
                children: [
                  // Current plan status
                  if (subscriptionState.subscription != null)
                    _buildCurrentPlanCard(context, subscriptionState),

                  // Referral benefit banner
                  _ReferralBenefitBanner(),

                  // Available plans header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text(
                      L.tr('subscription_available_plans'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  // Tier cards
                  ...AccountTier.values.map((tier) {
                    final isCurrentTier =
                        tier == subscriptionState.effectiveTier;
                    return TierCard(
                      tier: tier,
                      isCurrentTier: isCurrentTier,
                      isRecommended: TierBenefits.isRecommended(tier) &&
                          !isCurrentTier,
                      isLoading: _upgradingTier == tier,
                      onSelect: () => _handleTierSelect(tier),
                    );
                  }),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentPlanCard(
      BuildContext context, SubscriptionState subscriptionState) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subscription = subscriptionState.subscription!;
    final tierColor = TierBenefits.getColor(subscription.tier);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tierColor.withValues(alpha: 0.15),
            tierColor.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tierColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  subscription.tier.icon,
                  color: tierColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${subscription.tier.label} Plan',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: subscription.isActive
                                ? Colors.green.withValues(alpha: 0.2)
                                : Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            subscription.status.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: subscription.isActive
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (subscription.cancelAtPeriodEnd) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              L.tr('subscription_canceling'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Renewal/expiry info
          if (subscription.currentPeriodEnd != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  subscription.cancelAtPeriodEnd
                      ? Icons.event_busy
                      : Icons.event_repeat,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subscription.cancelAtPeriodEnd
                        ? 'Access ends ${_formatDate(subscription.currentPeriodEnd!)}'
                        : 'Renews ${_formatDate(subscription.currentPeriodEnd!)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (subscription.daysRemaining != null)
                  Text(
                    '${subscription.daysRemaining} days',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],

          // Cancel/Resume button
          if (subscription.isPaid && subscription.isActive) ...[
            const SizedBox(height: 16),
            if (subscription.cancelAtPeriodEnd)
              OutlinedButton.icon(
                onPressed: _handleResume,
                icon: const Icon(Icons.refresh),
                label: Text(L.tr('subscription_resume')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                ),
              )
            else
              TextButton.icon(
                onPressed: _showCancelConfirmation,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: Text(L.tr('subscription_cancel_subscription')),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _handleTierSelect(AccountTier tier) async {
    final currentTier = ref.read(subscriptionProvider).effectiveTier;

    if (tier == currentTier) return;

    if (tier == AccountTier.base) {
      // Downgrade to base = cancel subscription
      _showCancelConfirmation();
      return;
    }

    // Start upgrade
    setState(() => _upgradingTier = tier);

    try {
      final checkoutResponse = await ref
          .read(subscriptionProvider.notifier)
          .startUpgrade(tier);

      if (checkoutResponse == null) {
        // Check if there's an error in state
        if (mounted) {
          final error = ref.read(subscriptionProvider).error;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error ?? L.tr('subscription_upgrade_failed')),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      if (checkoutResponse.isDirectUpdate) {
        // Tier was changed directly (no payment sheet needed)
        await ref.read(subscriptionProvider.notifier).load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Plan changed to ${tier.label}!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }

      if (mounted) {
        // Initialize and present payment sheet
        await StripeService.instance.initPaymentSheet(
          paymentIntentClientSecret: checkoutResponse.clientSecret!,
          customerId: checkoutResponse.customerId!,
          customerEphemeralKeySecret: checkoutResponse.ephemeralKey!,
        );

        final success = await StripeService.instance.presentPaymentSheet();

        if (success && mounted) {
          // Refresh subscription after successful payment
          // Pass subscription ID to verify directly with Stripe
          await ref.read(subscriptionProvider.notifier).refreshAfterPayment(
            subscriptionId: checkoutResponse.subscriptionId,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Upgraded to ${tier.label}!'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upgrade: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _upgradingTier = null);
      }
    }
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.tr('subscription_cancel')),
        content: Text(L.tr('subscription_cancel_message')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleCancel();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(L.tr('subscription_cancel_plan')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L.tr('subscription_keep_plan')),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCancel() async {
    final success = await ref.read(subscriptionProvider.notifier).cancel();

    if (mounted) {
      if (success) {
        final sub = ref.read(subscriptionProvider).subscription;
        final endDate = sub?.currentPeriodEnd != null
            ? _formatDate(sub!.currentPeriodEnd!)
            : 'end of billing period';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plan canceled. Access continues until $endDate.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final error = ref.read(subscriptionProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error ?? L.tr('subscription_cancel_failed')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleResume() async {
    final success = await ref.read(subscriptionProvider.notifier).resume();

    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L.tr('subscription_resumed')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

class _ReferralBenefitBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referralState = ref.watch(referralProvider);
    final info = referralState.info;

    final currentTier = ref.watch(subscriptionProvider).effectiveTier;

    // Only show if user was referred, hasn't used the coupon, AND is on Base tier
    // (no point showing "upgrade" benefit if already on Pro or Enterprise)
    if (info == null || !info.hasUnusedSubscriptionBenefit || currentTier != AccountTier.base) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(14),
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
          const Icon(Icons.card_giftcard, color: Colors.amber, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              L.tr('subscription_referral_reward'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
