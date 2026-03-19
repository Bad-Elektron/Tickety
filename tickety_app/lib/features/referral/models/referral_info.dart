/// Referral information for the current user.
class ReferralInfo {
  final String referralCode;
  final String? referredByCode;
  final DateTime? referredAt;
  final int totalReferrals;
  final int totalEarningsCents;
  final int pendingEarningsCents;
  final int paidEarningsCents;
  final int withdrawableCents;
  final List<ChannelStat> channelStats;
  final bool hasReferralCoupon;

  const ReferralInfo({
    required this.referralCode,
    this.referredByCode,
    this.referredAt,
    this.totalReferrals = 0,
    this.totalEarningsCents = 0,
    this.pendingEarningsCents = 0,
    this.paidEarningsCents = 0,
    this.withdrawableCents = 0,
    this.channelStats = const [],
    this.hasReferralCoupon = false,
  });

  bool get wasReferred => referredByCode != null;

  bool get hasEarnings => totalEarningsCents > 0;

  bool get canWithdraw => withdrawableCents > 0;

  String get formattedTotalEarnings =>
      '\$${(totalEarningsCents / 100).toStringAsFixed(2)}';

  String get formattedPendingEarnings =>
      '\$${(pendingEarningsCents / 100).toStringAsFixed(2)}';

  String get formattedPaidEarnings =>
      '\$${(paidEarningsCents / 100).toStringAsFixed(2)}';

  String get formattedWithdrawable =>
      '\$${(withdrawableCents / 100).toStringAsFixed(2)}';

  /// Whether the referral discount is still active (within benefit window).
  bool get isDiscountActive {
    if (referredAt == null) return false;
    final daysSinceReferral = DateTime.now().difference(referredAt!).inDays;
    return daysSinceReferral < 365;
  }

  int get discountDaysRemaining {
    if (referredAt == null) return 0;
    final daysSinceReferral = DateTime.now().difference(referredAt!).inDays;
    return (365 - daysSinceReferral).clamp(0, 365);
  }

  /// Whether the referred user has an unused Pro subscription benefit.
  bool get hasUnusedSubscriptionBenefit => wasReferred && !hasReferralCoupon;

  ReferralInfo copyWith({
    String? referralCode,
    String? referredByCode,
    DateTime? referredAt,
    int? totalReferrals,
    int? totalEarningsCents,
    int? pendingEarningsCents,
    int? paidEarningsCents,
    int? withdrawableCents,
    List<ChannelStat>? channelStats,
    bool? hasReferralCoupon,
  }) {
    return ReferralInfo(
      referralCode: referralCode ?? this.referralCode,
      referredByCode: referredByCode ?? this.referredByCode,
      referredAt: referredAt ?? this.referredAt,
      totalReferrals: totalReferrals ?? this.totalReferrals,
      totalEarningsCents: totalEarningsCents ?? this.totalEarningsCents,
      pendingEarningsCents: pendingEarningsCents ?? this.pendingEarningsCents,
      paidEarningsCents: paidEarningsCents ?? this.paidEarningsCents,
      withdrawableCents: withdrawableCents ?? this.withdrawableCents,
      channelStats: channelStats ?? this.channelStats,
      hasReferralCoupon: hasReferralCoupon ?? this.hasReferralCoupon,
    );
  }
}

/// Stats for a specific referral channel.
class ChannelStat {
  final String channel;
  final int clicks;
  final int signups;
  final int purchases;
  final int earningsCents;

  const ChannelStat({
    required this.channel,
    this.clicks = 0,
    this.signups = 0,
    this.purchases = 0,
    this.earningsCents = 0,
  });

  String get formattedEarnings =>
      '\$${(earningsCents / 100).toStringAsFixed(2)}';

  double get signupRate => clicks > 0 ? signups / clicks : 0;

  String get displayName {
    switch (channel) {
      case 'instagram':
        return 'Instagram';
      case 'youtube':
        return 'YouTube';
      case 'tiktok':
        return 'TikTok';
      case 'twitter':
        return 'Twitter/X';
      case 'email':
        return 'Email';
      case 'website':
        return 'Website';
      default:
        return 'Other';
    }
  }
}

/// Leaderboard entry for admin dashboard.
class ReferralLeaderEntry {
  final String userId;
  final String? displayName;
  final int totalReferrals;
  final int totalEarningsCents;
  final String? topChannel;

  const ReferralLeaderEntry({
    required this.userId,
    this.displayName,
    this.totalReferrals = 0,
    this.totalEarningsCents = 0,
    this.topChannel,
  });

  String get formattedEarnings =>
      '\$${(totalEarningsCents / 100).toStringAsFixed(2)}';
}
