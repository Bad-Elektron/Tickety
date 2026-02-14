import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/referral/data/referral_repository.dart';
import '../../features/referral/models/referral_info.dart';
import '../errors/errors.dart';

const _tag = 'ReferralProvider';

/// Repository provider.
final referralRepositoryProvider = Provider<ReferralRepository>((ref) {
  return ReferralRepository();
});

/// State for referral info.
class ReferralState {
  final ReferralInfo? info;
  final bool isLoading;
  final String? error;

  const ReferralState({
    this.info,
    this.isLoading = false,
    this.error,
  });

  ReferralState copyWith({
    ReferralInfo? info,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ReferralState(
      info: info ?? this.info,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier for referral state.
class ReferralNotifier extends StateNotifier<ReferralState> {
  final ReferralRepository _repository;

  ReferralNotifier(this._repository) : super(const ReferralState());

  /// Load referral info.
  Future<void> load() async {
    if (state.isLoading) return;

    AppLogger.debug('Loading referral info', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final info = await _repository.getMyReferralInfo();
      AppLogger.info(
        'Referral info loaded: code=${info.referralCode}, referrals=${info.totalReferrals}',
        tag: _tag,
      );
      state = state.copyWith(info: info, isLoading: false);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load referral info',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
    }
  }

  /// Refresh referral info.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: false);
    await load();
  }
}

/// Provider for referral state.
final referralProvider =
    StateNotifierProvider<ReferralNotifier, ReferralState>((ref) {
  final repository = ref.watch(referralRepositoryProvider);
  return ReferralNotifier(repository);
});
