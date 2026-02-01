import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/payments/data/i_resale_repository.dart';
import '../../features/payments/data/resale_repository.dart';
import '../../features/payments/models/seller_balance.dart';
import '../errors/errors.dart';

const _tag = 'SellerBalanceProvider';

/// State for the seller's wallet balance.
class SellerBalanceState {
  final SellerBalance? balance;
  final bool isLoading;
  final String? error;
  final WithdrawalResult? lastWithdrawal;
  final bool isWithdrawing;

  const SellerBalanceState({
    this.balance,
    this.isLoading = false,
    this.error,
    this.lastWithdrawal,
    this.isWithdrawing = false,
  });

  SellerBalanceState copyWith({
    SellerBalance? balance,
    bool? isLoading,
    String? error,
    WithdrawalResult? lastWithdrawal,
    bool? isWithdrawing,
    bool clearError = false,
    bool clearWithdrawal = false,
  }) {
    return SellerBalanceState(
      balance: balance ?? this.balance,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      lastWithdrawal:
          clearWithdrawal ? null : (lastWithdrawal ?? this.lastWithdrawal),
      isWithdrawing: isWithdrawing ?? this.isWithdrawing,
    );
  }

  bool get hasError => error != null;
  bool get hasBalance => balance != null;
  bool get hasAccount => balance?.hasAccount ?? false;
  bool get canWithdraw => balance?.canWithdraw ?? false;
}

/// Notifier for managing seller balance state.
class SellerBalanceNotifier extends StateNotifier<SellerBalanceState> {
  final IResaleRepository _repository;

  SellerBalanceNotifier(this._repository) : super(const SellerBalanceState());

  /// Load the seller's balance from Stripe.
  Future<void> loadBalance() async {
    if (state.isLoading) return;

    AppLogger.debug('Loading seller balance', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final balance = await _repository.getSellerBalance();
      AppLogger.info('Loaded seller balance: $balance', tag: _tag);
      state = state.copyWith(
        balance: balance,
        isLoading: false,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load seller balance',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
    }
  }

  /// Refresh the balance (for pull-to-refresh).
  Future<void> refresh() async {
    state = state.copyWith(isLoading: false);
    await loadBalance();
  }

  /// Create a seller account if one doesn't exist.
  Future<bool> ensureSellerAccount() async {
    if (state.hasAccount) return true;

    AppLogger.info('Creating seller account', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _repository.createSellerAccount();
      // Reload balance to get updated state
      await loadBalance();
      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to create seller account',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
      return false;
    }
  }

  /// Initiate a withdrawal from the seller's Stripe balance.
  ///
  /// If [amountCents] is null, withdraws the full available balance.
  /// Returns the withdrawal result, which may include an onboarding URL
  /// if the seller needs to add bank details first.
  Future<WithdrawalResult?> initiateWithdrawal({int? amountCents}) async {
    if (state.isWithdrawing) return null;

    AppLogger.info(
      'Initiating withdrawal${amountCents != null ? " for $amountCents cents" : ""}',
      tag: _tag,
    );
    state = state.copyWith(
      isWithdrawing: true,
      clearError: true,
      clearWithdrawal: true,
    );

    try {
      final result = await _repository.initiateWithdrawal(
        amountCents: amountCents,
      );

      AppLogger.info('Withdrawal result: $result', tag: _tag);

      if (result.success) {
        // Update the cached balance
        final currentBalance = state.balance;
        if (currentBalance != null && result.remainingBalanceCents != null) {
          state = state.copyWith(
            balance: SellerBalance(
              hasAccount: currentBalance.hasAccount,
              availableBalanceCents: result.remainingBalanceCents!,
              pendingBalanceCents: currentBalance.pendingBalanceCents,
              payoutsEnabled: currentBalance.payoutsEnabled,
              detailsSubmitted: currentBalance.detailsSubmitted,
              needsOnboarding: currentBalance.needsOnboarding,
              currency: currentBalance.currency,
            ),
            isWithdrawing: false,
            lastWithdrawal: result,
          );
        } else {
          state = state.copyWith(
            isWithdrawing: false,
            lastWithdrawal: result,
          );
        }
      } else {
        state = state.copyWith(
          isWithdrawing: false,
          lastWithdrawal: result,
        );
      }

      return result;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to initiate withdrawal',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isWithdrawing: false,
        error: appError.userMessage,
      );
      return null;
    }
  }

  /// Clear the last withdrawal result.
  void clearWithdrawal() {
    state = state.copyWith(clearWithdrawal: true);
  }

  /// Clear any error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ============================================================
// PROVIDERS
// ============================================================

/// Repository provider - reuses the existing resale repository.
final _sellerRepositoryProvider = Provider<IResaleRepository>((ref) {
  return ResaleRepository();
});

/// Main provider for seller balance state.
final sellerBalanceProvider =
    StateNotifierProvider<SellerBalanceNotifier, SellerBalanceState>((ref) {
  final repository = ref.watch(_sellerRepositoryProvider);
  return SellerBalanceNotifier(repository);
});

/// Convenience provider for checking if seller has an account.
final hasSellerAccountProvider = Provider<bool>((ref) {
  return ref.watch(sellerBalanceProvider).hasAccount;
});

/// Convenience provider for the formatted available balance.
final availableBalanceProvider = Provider<String>((ref) {
  return ref.watch(sellerBalanceProvider).balance?.formattedAvailableBalance ??
      '\$0.00';
});

/// Convenience provider for the formatted pending balance.
final pendingBalanceProvider = Provider<String>((ref) {
  return ref.watch(sellerBalanceProvider).balance?.formattedPendingBalance ??
      '\$0.00';
});

/// Convenience provider for checking if seller can withdraw.
final canWithdrawProvider = Provider<bool>((ref) {
  return ref.watch(sellerBalanceProvider).canWithdraw;
});

/// Convenience provider for checking if payouts are enabled.
final payoutsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(sellerBalanceProvider).balance?.payoutsEnabled ?? false;
});

/// Convenience provider for checking if balance is loading.
final sellerBalanceLoadingProvider = Provider<bool>((ref) {
  return ref.watch(sellerBalanceProvider).isLoading;
});

/// Convenience provider for balance error state.
final sellerBalanceErrorProvider = Provider<String?>((ref) {
  return ref.watch(sellerBalanceProvider).error;
});
