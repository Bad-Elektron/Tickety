import '../../../core/state/app_state.dart';

/// Sections of the analytics dashboard that can be gated by tier.
enum AnalyticsSection {
  summaryCards('Summary Cards'),
  checkInProgress('Check-in Progress'),
  ticketTypeBreakdown('Ticket Type Breakdown'),
  hourlyCheckins('Hourly Check-ins'),
  usherPerformance('Usher Performance');

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

  // ── Analytics access ────────────────────────────────────────

  static const Map<AccountTier, Set<AnalyticsSection>> _analyticsAccess = {
    AccountTier.base: {AnalyticsSection.summaryCards},
    AccountTier.pro: {
      AnalyticsSection.summaryCards,
      AnalyticsSection.checkInProgress,
      AnalyticsSection.ticketTypeBreakdown,
    },
    AccountTier.enterprise: {
      AnalyticsSection.summaryCards,
      AnalyticsSection.checkInProgress,
      AnalyticsSection.ticketTypeBreakdown,
      AnalyticsSection.hourlyCheckins,
      AnalyticsSection.usherPerformance,
    },
  };

  // ── Public accessors ────────────────────────────────────────

  static int getMaxUshers(AccountTier tier) => _maxUshers[tier] ?? 3;
  static int getMaxSellers(AccountTier tier) => _maxSellers[tier] ?? 3;
  static int getMaxManagers(AccountTier tier) => _maxManagers[tier] ?? 1;
  static int getMaxTicketTypes(AccountTier tier) => _maxTicketTypes[tier] ?? 3;
  static int getMaxActiveEvents(AccountTier tier) => _maxActiveEvents[tier] ?? 3;

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
