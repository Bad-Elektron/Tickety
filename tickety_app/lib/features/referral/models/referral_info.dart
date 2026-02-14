/// Referral information for the current user.
class ReferralInfo {
  final String referralCode;
  final String? referredByCode;
  final DateTime? referredAt;
  final int totalReferrals;
  final int totalEarningsCents;
  final int pendingEarningsCents;

  const ReferralInfo({
    required this.referralCode,
    this.referredByCode,
    this.referredAt,
    this.totalReferrals = 0,
    this.totalEarningsCents = 0,
    this.pendingEarningsCents = 0,
  });

  bool get wasReferred => referredByCode != null;

  bool get hasEarnings => totalEarningsCents > 0;

  String get formattedTotalEarnings =>
      '\$${(totalEarningsCents / 100).toStringAsFixed(2)}';

  String get formattedPendingEarnings =>
      '\$${(pendingEarningsCents / 100).toStringAsFixed(2)}';

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

  ReferralInfo copyWith({
    String? referralCode,
    String? referredByCode,
    DateTime? referredAt,
    int? totalReferrals,
    int? totalEarningsCents,
    int? pendingEarningsCents,
  }) {
    return ReferralInfo(
      referralCode: referralCode ?? this.referralCode,
      referredByCode: referredByCode ?? this.referredByCode,
      referredAt: referredAt ?? this.referredAt,
      totalReferrals: totalReferrals ?? this.totalReferrals,
      totalEarningsCents: totalEarningsCents ?? this.totalEarningsCents,
      pendingEarningsCents: pendingEarningsCents ?? this.pendingEarningsCents,
    );
  }
}
