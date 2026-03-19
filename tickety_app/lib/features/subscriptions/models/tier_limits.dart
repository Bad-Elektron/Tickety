import '../../../core/state/app_state.dart';

/// Sections of the analytics dashboard that can be gated by tier.
enum AnalyticsSection {
  summaryCards('Summary Cards'),
  checkInProgress('Check-in Progress'),
  ticketTypeBreakdown('Ticket Type Breakdown'),
  hourlyCheckins('Hourly Check-ins'),
  usherPerformance('Usher Performance'),
  platformTrends('Platform Trends'),
  marketComparison('Market Comparison'),
  tagPerformance('Tag Performance');

  const AnalyticsSection(this.label);

  final String label;
}

/// Single source of truth for all subscription tier limits.
///
/// Defines numeric caps and feature access per [AccountTier].
class TierLimits {
  TierLimits._();

  // ── Staff limits per event ──────────────────────────────────

  static const Map<AccountTier, int> _maxUshers = {
    AccountTier.base: 3,
    AccountTier.pro: 15,
    AccountTier.enterprise: 999,
  };

  static const Map<AccountTier, int> _maxSellers = {
    AccountTier.base: 3,
    AccountTier.pro: 15,
    AccountTier.enterprise: 999,
  };

  static const Map<AccountTier, int> _maxManagers = {
    AccountTier.base: 1,
    AccountTier.pro: 5,
    AccountTier.enterprise: 999,
  };

  // ── Ticket type limits per event ────────────────────────────

  static const Map<AccountTier, int> _maxTicketTypes = {
    AccountTier.base: 3,
    AccountTier.pro: 10,
    AccountTier.enterprise: 999,
  };

  // ── Active event limits ───────────────────────────────────

  static const Map<AccountTier, int> _maxActiveEvents = {
    AccountTier.base: 3,
    AccountTier.pro: 10,
    AccountTier.enterprise: 999,
  };

  // ── Tag limits per event ──────────────────────────────────

  static const Map<AccountTier, int> _maxTags = {
    AccountTier.base: 3,
    AccountTier.pro: 5,
    AccountTier.enterprise: 10,
  };

  static const Map<AccountTier, bool> _customTagsAllowed = {
    AccountTier.base: false,
    AccountTier.pro: true,
    AccountTier.enterprise: true,
  };

  // ── Venue builder access ──────────────────────────────────
  static const Map<AccountTier, bool> _venueBuilderAccess = {
    AccountTier.base: false,
    AccountTier.pro: false,
    AccountTier.enterprise: true,
  };

  // ── Merch store access ──────────────────────────────────
  static const Map<AccountTier, bool> _merchStoreAccess = {
    AccountTier.base: false,
    AccountTier.pro: false,
    AccountTier.enterprise: true,
  };

  // ── Branding access ────────────────────────────────────
  static const Map<AccountTier, bool> _brandingAccess = {
    AccountTier.base: false,
    AccountTier.pro: true,
    AccountTier.enterprise: true,
  };

  // ── Embed widget access ─────────────────────────────────
  static const Map<AccountTier, bool> _widgetAccess = {
    AccountTier.base: true,   // Base gets widget with "Powered by Tickety" branding
    AccountTier.pro: true,
    AccountTier.enterprise: true,
  };

  // ── Analytics access ────────────────────────────────────────

  static const Map<AccountTier, Set<AnalyticsSection>> _analyticsAccess = {
    AccountTier.base: {AnalyticsSection.summaryCards},
    AccountTier.pro: {
      AnalyticsSection.summaryCards,
      AnalyticsSection.checkInProgress,
      AnalyticsSection.ticketTypeBreakdown,
      AnalyticsSection.hourlyCheckins,
      AnalyticsSection.usherPerformance,
    },
    AccountTier.enterprise: {
      AnalyticsSection.summaryCards,
      AnalyticsSection.checkInProgress,
      AnalyticsSection.ticketTypeBreakdown,
      AnalyticsSection.hourlyCheckins,
      AnalyticsSection.usherPerformance,
      AnalyticsSection.platformTrends,
      AnalyticsSection.marketComparison,
      AnalyticsSection.tagPerformance,
    },
  };

  // ── Public accessors ────────────────────────────────────────

  static int getMaxUshers(AccountTier tier) => _maxUshers[tier] ?? 3;
  static int getMaxSellers(AccountTier tier) => _maxSellers[tier] ?? 3;
  static int getMaxManagers(AccountTier tier) => _maxManagers[tier] ?? 1;
  static int getMaxTicketTypes(AccountTier tier) => _maxTicketTypes[tier] ?? 3;
  static int getMaxActiveEvents(AccountTier tier) => _maxActiveEvents[tier] ?? 3;
  static int getMaxTags(AccountTier tier) => _maxTags[tier] ?? 3;
  static bool canUseCustomTags(AccountTier tier) => _customTagsAllowed[tier] ?? false;
  static bool canUseVenueBuilder(AccountTier tier) => _venueBuilderAccess[tier] ?? false;
  static bool canUseMerchStore(AccountTier tier) => _merchStoreAccess[tier] ?? false;
  static bool canCustomizeBranding(AccountTier tier) => _brandingAccess[tier] ?? false;
  static bool canUseWidget(AccountTier tier) => _widgetAccess[tier] ?? false;

  /// Whether [tier] can view the given analytics [section].
  static bool canViewAnalytics(AccountTier tier, AnalyticsSection section) {
    return _analyticsAccess[tier]?.contains(section) ?? false;
  }

  /// All analytics sections available to [tier].
  static Set<AnalyticsSection> getAnalyticsSections(AccountTier tier) {
    return _analyticsAccess[tier] ?? {};
  }

  /// The lowest tier that grants access to [section].
  static AccountTier minimumTierFor(AnalyticsSection section) {
    for (final tier in AccountTier.values) {
      if (canViewAnalytics(tier, section)) return tier;
    }
    return AccountTier.enterprise;
  }

  /// Get the max staff count for a given role.
  static int getMaxForRole(AccountTier tier, String roleValue) {
    return switch (roleValue) {
      'usher' => getMaxUshers(tier),
      'seller' => getMaxSellers(tier),
      'manager' => getMaxManagers(tier),
      _ => 0,
    };
  }
}
