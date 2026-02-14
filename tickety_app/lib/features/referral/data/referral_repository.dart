import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/referral_info.dart';

const _tag = 'ReferralRepository';

/// Repository for referral system operations.
class ReferralRepository {
  final _client = SupabaseService.instance.client;

  /// Get the current user's referral info including code, stats, and earnings.
  Future<ReferralInfo> getMyReferralInfo() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.debug('Fetching referral info for user: $userId', tag: _tag);

    try {
      // Get profile with referral code and referral info
      final profileResponse = await _client
          .from('profiles')
          .select('referral_code, referred_by, referred_at')
          .eq('id', userId)
          .single();

      final referralCode = profileResponse['referral_code'] as String? ?? '';

      // Get referrer's code if the user was referred
      String? referredByCode;
      final referredBy = profileResponse['referred_by'] as String?;
      if (referredBy != null) {
        final referrerResponse = await _client
            .from('profiles')
            .select('referral_code')
            .eq('id', referredBy)
            .maybeSingle();
        referredByCode = referrerResponse?['referral_code'] as String?;
      }

      // Count total referrals (users who used this user's code)
      final referralsResponse = await _client
          .from('profiles')
          .select('id')
          .eq('referred_by', userId);
      final totalReferrals = (referralsResponse as List).length;

      // Sum earnings
      int totalEarningsCents = 0;
      int pendingEarningsCents = 0;

      final earningsResponse = await _client
          .from('referral_earnings')
          .select('earning_cents, status')
          .eq('referrer_id', userId);

      for (final row in earningsResponse as List) {
        final cents = row['earning_cents'] as int? ?? 0;
        final status = row['status'] as String?;
        if (status == 'pending') {
          pendingEarningsCents += cents;
        }
        if (status != 'cancelled') {
          totalEarningsCents += cents;
        }
      }

      final referredAtStr = profileResponse['referred_at'] as String?;

      AppLogger.info(
        'Referral info loaded: code=$referralCode, referrals=$totalReferrals, earnings=$totalEarningsCents',
        tag: _tag,
      );

      return ReferralInfo(
        referralCode: referralCode,
        referredByCode: referredByCode,
        referredAt: referredAtStr != null ? DateTime.parse(referredAtStr) : null,
        totalReferrals: totalReferrals,
        totalEarningsCents: totalEarningsCents,
        pendingEarningsCents: pendingEarningsCents,
      );
    } catch (e, s) {
      AppLogger.error(
        'Failed to load referral info',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      throw ErrorHandler.normalize(e, s);
    }
  }
}
