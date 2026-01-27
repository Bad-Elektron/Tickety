import 'package:flutter/material.dart';

import '../../../core/state/app_state.dart';

/// Benefits and pricing information for each subscription tier.
class TierBenefits {
  /// Monthly price in cents for each tier.
  static const Map<AccountTier, int> pricesMonthly = {
    AccountTier.base: 0,
    AccountTier.pro: 999, // $9.99/month
    AccountTier.enterprise: 2999, // $29.99/month
  };

  /// Yearly price in cents for each tier (with discount).
  static const Map<AccountTier, int> pricesYearly = {
    AccountTier.base: 0,
    AccountTier.pro: 9990, // $99.90/year (save ~$20)
    AccountTier.enterprise: 29990, // $299.90/year (save ~$60)
  };

  /// List of features for each tier.
  static const Map<AccountTier, List<String>> features = {
    AccountTier.base: [
      'Browse and discover events',
      'Purchase tickets',
      'Basic ticket management',
      'Email support',
    ],
    AccountTier.pro: [
      'Everything in Base',
      'Create unlimited events',
      'Advanced analytics dashboard',
      'Custom event branding',
      'Priority support',
      'Early access to new features',
    ],
    AccountTier.enterprise: [
      'Everything in Pro',
      'Unlimited staff members',
      'API access',
      'Custom integrations',
      'Dedicated account manager',
      'White-label options',
      'SLA guarantee',
    ],
  };

  /// Short description for each tier.
  static const Map<AccountTier, String> descriptions = {
    AccountTier.base: 'Perfect for event attendees',
    AccountTier.pro: 'For event organizers and creators',
    AccountTier.enterprise: 'For large organizations and venues',
  };

  /// Whether the tier is recommended.
  static bool isRecommended(AccountTier tier) => tier == AccountTier.pro;

  /// Get formatted monthly price string.
  static String getMonthlyPriceString(AccountTier tier) {
    final cents = pricesMonthly[tier] ?? 0;
    if (cents == 0) return 'Free';
    return '\$${(cents / 100).toStringAsFixed(2)}/mo';
  }

  /// Get formatted yearly price string.
  static String getYearlyPriceString(AccountTier tier) {
    final cents = pricesYearly[tier] ?? 0;
    if (cents == 0) return 'Free';
    return '\$${(cents / 100).toStringAsFixed(2)}/yr';
  }

  /// Get savings amount when paying yearly.
  static int getYearlySavings(AccountTier tier) {
    final monthly = pricesMonthly[tier] ?? 0;
    final yearly = pricesYearly[tier] ?? 0;
    return (monthly * 12) - yearly;
  }

  /// Get the tier icon.
  static IconData getIcon(AccountTier tier) => tier.icon;

  /// Get the tier color.
  static Color getColor(AccountTier tier) => Color(tier.color);

  /// Get all features for a tier, including inherited features.
  static List<String> getAllFeatures(AccountTier tier) {
    return features[tier] ?? [];
  }

  /// Check if a specific feature is included in a tier.
  static bool hasFeature(AccountTier tier, String feature) {
    final tierFeatures = features[tier] ?? [];
    return tierFeatures.contains(feature);
  }
}
