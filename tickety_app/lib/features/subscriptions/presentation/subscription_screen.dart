import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        title: const Text('Subscription'),
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

                  // Available plans header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text(
                      'Available Plans',
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

                  // Manage billing section
                  if (subscriptionState.isPaid)
                    _buildManageBillingCard(context),

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
                              'Canceling',
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
                label: const Text('Resume Subscription'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                ),
              )
            else
              TextButton.icon(
                onPressed: _showCancelConfirmation,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel Subscription'),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildManageBillingCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openBillingPortal,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.credit_card,
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
                        'Manage Payment Methods',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Update billing info, view invoices',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
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
              content: Text(error ?? 'Failed to start upgrade. Please try again.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      if (mounted) {
        // Initialize and present payment sheet
        await StripeService.instance.initPaymentSheet(
          paymentIntentClientSecret: checkoutResponse.clientSecret,
          customerId: checkoutResponse.customerId,
          customerEphemeralKeySecret: checkoutResponse.ephemeralKey,
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
        title: const Text('Cancel Subscription?'),
        content: const Text(
          'Your subscription will remain active until the end of the current billing period. '
          'After that, you\'ll be downgraded to the Base plan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep Subscription'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _handleCancel();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCancel() async {
    final success = await ref.read(subscriptionProvider.notifier).cancel();

    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription will cancel at end of billing period'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleResume() async {
    final success = await ref.read(subscriptionProvider.notifier).resume();

    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription resumed'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _openBillingPortal() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening billing portal...'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );

    // Note: In a real implementation, you would:
    // 1. Call the repository to get the portal URL
    // 2. Open the URL in a web browser or WebView
    // For now, show a placeholder message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Billing portal coming soon'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
