import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/subscription_provider.dart';
import '../state/app_state.dart';
import '../../features/subscriptions/models/tier_benefits.dart';

/// Utility for gating features behind subscription tiers.
class FeatureGate {
  /// Check if the current user has access to a feature requiring the specified tier.
  ///
  /// Returns true if the user's subscription tier is >= the required tier.
  static bool hasAccess(WidgetRef ref, AccountTier requiredTier) {
    final currentTier = ref.read(currentTierProvider);
    final currentIndex = AccountTier.values.indexOf(currentTier);
    final requiredIndex = AccountTier.values.indexOf(requiredTier);
    return currentIndex >= requiredIndex;
  }

  /// Watch and return whether the current user has access to a feature.
  ///
  /// Use this when you need reactive updates when the tier changes.
  static bool watchAccess(WidgetRef ref, AccountTier requiredTier) {
    final currentTier = ref.watch(currentTierProvider);
    final currentIndex = AccountTier.values.indexOf(currentTier);
    final requiredIndex = AccountTier.values.indexOf(requiredTier);
    return currentIndex >= requiredIndex;
  }

  /// Widget that shows either the child or an upgrade prompt based on access.
  ///
  /// Example:
  /// ```dart
  /// FeatureGate.gated(
  ///   ref: ref,
  ///   requiredTier: AccountTier.pro,
  ///   child: ProFeatureWidget(),
  ///   // Optional: custom locked widget
  ///   lockedBuilder: (context, requiredTier) => CustomLockedWidget(),
  /// )
  /// ```
  static Widget gated({
    required WidgetRef ref,
    required AccountTier requiredTier,
    required Widget child,
    Widget Function(BuildContext, AccountTier)? lockedBuilder,
  }) {
    if (watchAccess(ref, requiredTier)) {
      return child;
    }
    return _GatedFeatureWidget(
      requiredTier: requiredTier,
      lockedBuilder: lockedBuilder,
    );
  }

  /// Consumer widget wrapper for gating features.
  ///
  /// Use this when you need a Consumer to access ref inside a StatelessWidget.
  ///
  /// Example:
  /// ```dart
  /// FeatureGate.consumer(
  ///   requiredTier: AccountTier.enterprise,
  ///   builder: (context, ref) => EnterpriseFeature(),
  /// )
  /// ```
  static Widget consumer({
    required AccountTier requiredTier,
    required Widget Function(BuildContext, WidgetRef) builder,
    Widget Function(BuildContext, AccountTier)? lockedBuilder,
  }) {
    return Consumer(
      builder: (context, ref, _) {
        if (watchAccess(ref, requiredTier)) {
          return builder(context, ref);
        }
        if (lockedBuilder != null) {
          return lockedBuilder(context, requiredTier);
        }
        return _GatedFeatureWidget(
          requiredTier: requiredTier,
          lockedBuilder: lockedBuilder,
        );
      },
    );
  }
}

/// Default widget shown when a feature is gated.
class _GatedFeatureWidget extends StatelessWidget {
  const _GatedFeatureWidget({
    required this.requiredTier,
    this.lockedBuilder,
  });

  final AccountTier requiredTier;
  final Widget Function(BuildContext, AccountTier)? lockedBuilder;

  @override
  Widget build(BuildContext context) {
    if (lockedBuilder != null) {
      return lockedBuilder!(context, requiredTier);
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tierColor = TierBenefits.getColor(requiredTier);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tierColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 48,
            color: tierColor.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            '${requiredTier.label} Feature',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upgrade to ${requiredTier.label} to unlock this feature',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              // Navigate to subscription screen
              Navigator.pushNamed(context, '/settings/subscription');
            },
            icon: Icon(requiredTier.icon),
            label: const Text('Upgrade'),
            style: FilledButton.styleFrom(
              backgroundColor: tierColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Extension on AccountTier for easy tier comparison.
extension AccountTierAccess on AccountTier {
  /// Check if this tier has access to the required tier level.
  bool hasAccessTo(AccountTier required) {
    final thisIndex = AccountTier.values.indexOf(this);
    final requiredIndex = AccountTier.values.indexOf(required);
    return thisIndex >= requiredIndex;
  }
}
