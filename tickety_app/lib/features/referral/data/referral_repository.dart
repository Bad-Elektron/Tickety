import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/referral_info.dart';

const _tag = 'ReferralRepository';

/// Repository for referral system operations.
class ReferralRepository {
  final _client = SupabaseService.instance.client;

  /// Get the current user's referral info including code, stats, earnings, and channels.
  Future<ReferralInfo> getMyReferralInfo() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.debug('Fetching referral info for user: $userId', tag: _tag);

    try {
      // Get profile with referral code and referral info
      Map<String, dynamic> profileResponse;
      try {
        profileResponse = await _client
            .from('profiles')
            .select(
                'referral_code, referred_by, referred_at, referral_coupon_id')
            .eq('id', userId)
            .single();
      } catch (_) {
        // Fallback if referral_coupon_id column doesn't exist yet
        profileResponse = await _client
            .from('profiles')
            .select('referral_code, referred_by, referred_at')
            .eq('id', userId)
            .single();
      }

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

      // Get balance via RPC (may not exist if migration not pushed)
      int totalEarningsCents = 0;
      int pendingEarningsCents = 0;
      int paidEarningsCents = 0;
      int withdrawableCents = 0;

      try {
        final balanceResponse = await _client.rpc(
          'get_referral_balance',
          params: {'p_user_id': userId},
        );

        if (balanceResponse != null) {
          final balance = balanceResponse is List
              ? (balanceResponse.isNotEmpty ? balanceResponse[0] : null)
              : balanceResponse;
          if (balance != null) {
            totalEarningsCents = (balance['total_cents'] as num?)?.toInt() ?? 0;
            pendingEarningsCents =
                (balance['pending_cents'] as num?)?.toInt() ?? 0;
            paidEarningsCents = (balance['paid_cents'] as num?)?.toInt() ?? 0;
            withdrawableCents =
                (balance['withdrawable_cents'] as num?)?.toInt() ?? 0;
          }
        }
      } catch (_) {
        // Fallback: query earnings directly if RPC doesn't exist yet
        try {
          final earningsResponse = await _client
              .from('referral_earnings')
              .select('earning_cents, status')
              .eq('referrer_id', userId);

          for (final row in earningsResponse as List) {
            final cents = row['earning_cents'] as int? ?? 0;
            final status = row['status'] as String?;
            if (status == 'pending') pendingEarningsCents += cents;
            if (status != 'cancelled') totalEarningsCents += cents;
          }
        } catch (_) {
          // No earnings table either — that's fine, show zeros
        }
      }

      // Get channel stats (may not exist if migration not pushed)
      List<ChannelStat> channelStats = [];
      try {
        channelStats = await getChannelStats();
      } catch (_) {
        // Channel stats table doesn't exist yet
      }

      final referredAtStr = profileResponse['referred_at'] as String?;
      final hasCoupon = profileResponse['referral_coupon_id'] != null;

      AppLogger.info(
        'Referral info loaded: code=$referralCode, referrals=$totalReferrals, '
        'earnings=$totalEarningsCents, withdrawable=$withdrawableCents',
        tag: _tag,
      );

      return ReferralInfo(
        referralCode: referralCode,
        referredByCode: referredByCode,
        referredAt:
            referredAtStr != null ? DateTime.parse(referredAtStr) : null,
        totalReferrals: totalReferrals,
        totalEarningsCents: totalEarningsCents,
        pendingEarningsCents: pendingEarningsCents,
        paidEarningsCents: paidEarningsCents,
        withdrawableCents: withdrawableCents,
        channelStats: channelStats,
        hasReferralCoupon: hasCoupon,
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

  /// Get channel stats for the current user.
  Future<List<ChannelStat>> getChannelStats() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client.rpc(
        'get_referral_funnel_stats',
        params: {'p_user_id': userId},
      );

      if (response == null) return [];

      final list = response as List;
      return list.map((row) {
        return ChannelStat(
          channel: row['channel'] as String? ?? 'other',
          clicks: (row['clicks'] as num?)?.toInt() ?? 0,
          signups: (row['signups'] as num?)?.toInt() ?? 0,
          purchases: (row['purchases'] as num?)?.toInt() ?? 0,
          earningsCents: (row['earnings_cents'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (e) {
      AppLogger.error('Failed to load channel stats', error: e, tag: _tag);
      return [];
    }
  }

  /// Withdraw referral earnings.
  /// Returns a map with success/failure info, onboarding URL if needed.
  Future<Map<String, dynamic>> withdrawEarnings() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info('Initiating referral earnings withdrawal', tag: _tag);

    try {
      final response = await _client.functions.invoke(
        'withdraw-referral-earnings',
        body: {},
      );

      final data = response.data as Map<String, dynamic>;

      if (data['success'] == true) {
        AppLogger.info(
          'Withdrawal successful: ${data['amount_cents']} cents',
          tag: _tag,
        );
      } else if (data['needs_onboarding'] == true) {
        AppLogger.info('User needs Stripe onboarding for withdrawal', tag: _tag);
      }

      return data;
    } catch (e, s) {
      AppLogger.error(
        'Failed to withdraw referral earnings',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      throw ErrorHandler.normalize(e, s);
    }
  }

  /// Track a referral click (called before signup, public endpoint).
  Future<void> trackClick({
    required String referralCode,
    required String channel,
  }) async {
    try {
      await _client.functions.invoke(
        'track-referral-click',
        body: {
          'referral_code': referralCode,
          'channel': channel,
        },
      );
      AppLogger.debug(
        'Tracked referral click: code=$referralCode, channel=$channel',
        tag: _tag,
      );
    } catch (e) {
      AppLogger.error('Failed to track referral click', error: e, tag: _tag);
      // Don't throw — tracking is best-effort
    }
  }

  /// Get leaderboard (admin).
  Future<List<ReferralLeaderEntry>> getLeaderboard({int limit = 20}) async {
    try {
      final response = await _client.rpc(
        'get_referral_leaderboard',
        params: {'p_limit': limit},
      );

      if (response == null) return [];

      final list = response as List;
      return list.map((row) {
        return ReferralLeaderEntry(
          userId: row['user_id'] as String,
          displayName: row['display_name'] as String?,
          totalReferrals: (row['total_referrals'] as num?)?.toInt() ?? 0,
          totalEarningsCents:
              (row['total_earnings_cents'] as num?)?.toInt() ?? 0,
          topChannel: row['top_channel'] as String?,
        );
      }).toList();
    } catch (e, s) {
      AppLogger.error(
        'Failed to load referral leaderboard',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      throw ErrorHandler.normalize(e, s);
    }
  }
}
