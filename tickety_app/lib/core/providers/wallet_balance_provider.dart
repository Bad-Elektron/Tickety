import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/wallet/data/wallet_repository.dart';
import '../../features/wallet/models/wallet_balance.dart';
import '../errors/errors.dart';

const _tag = 'WalletBalanceProvider';

/// State for the user's Tickety Wallet.
class WalletBalanceState {
  final WalletBalance? balance;
  final bool isLoading;
  final String? error;
  final bool isTopUpProcessing;
  final bool isPurchasing;

  const WalletBalanceState({
    this.balance,
    this.isLoading = false,
    this.error,
    this.isTopUpProcessing = false,
    this.isPurchasing = false,
  });

  WalletBalanceState copyWith({
    WalletBalance? balance,
    bool? isLoading,
    String? error,
    bool? isTopUpProcessing,
    bool? isPurchasing,
    bool clearError = false,
  }) {
    return WalletBalanceState(
      balance: balance ?? this.balance,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isTopUpProcessing: isTopUpProcessing ?? this.isTopUpProcessing,
      isPurchasing: isPurchasing ?? this.isPurchasing,
    );
  }

  bool get hasError => error != null;
  bool get hasBalance => balance != null;
  bool get hasFunds => balance?.hasFunds ?? false;
  int get availableCents => balance?.availableCents ?? 0;
}

/// Notifier for managing wallet balance state.
class WalletBalanceNotifier extends StateNotifier<WalletBalanceState> {
  final WalletRepository _repository;

  WalletBalanceNotifier(this._repository) : super(const WalletBalanceState());

  /// Load the wallet balance.
  Future<void> loadBalance() async {
    if (state.isLoading) return;

    AppLogger.debug('Loading wallet balance', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final balance = await _repository.getWalletBalance();
      AppLogger.info('Loaded wallet balance: $balance', tag: _tag);
      state = state.copyWith(balance: balance, isLoading: false);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load wallet balance',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
    }
  }

  /// Refresh the wallet balance.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: false);
    await loadBalance();
  }

  /// Create a wallet top-up via ACH.
  Future<bool> topUp({
    required int amountCents,
    required String paymentMethodId,
  }) async {
    if (state.isTopUpProcessing) return false;

    AppLogger.info('Creating wallet top-up: $amountCents cents', tag: _tag);
    state = state.copyWith(isTopUpProcessing: true, clearError: true);

    try {
      final result = await _repository.createWalletTopUp(
        amountCents: amountCents,
        paymentMethodId: paymentMethodId,
      );

      AppLogger.info('Top-up created: ${result['payment_intent_id']}', tag: _tag);

      // Update local balance with new pending amount
      final currentBalance = state.balance ?? const WalletBalance.empty();
      state = state.copyWith(
        isTopUpProcessing: false,
        balance: currentBalance.copyWith(
          pendingCents: result['pending_cents'] as int? ??
              (currentBalance.pendingCents + amountCents),
        ),
      );

      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to create wallet top-up',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isTopUpProcessing: false,
        error: appError.userMessage,
      );
      return false;
    }
  }

  /// Purchase tickets from wallet balance.
  Future<Map<String, dynamic>?> purchaseFromWallet({
    required String eventId,
    required int quantity,
  }) async {
    if (state.isPurchasing) return null;

    AppLogger.info('Wallet purchase: event=$eventId, qty=$quantity', tag: _tag);
    state = state.copyWith(isPurchasing: true, clearError: true);

    try {
      final result = await _repository.purchaseFromWallet(
        eventId: eventId,
        quantity: quantity,
      );

      AppLogger.info('Wallet purchase completed: ${result['payment_id']}', tag: _tag);

      // Update local balance
      final newBalanceCents = result['new_balance_cents'] as int? ?? 0;
      final currentBalance = state.balance ?? const WalletBalance.empty();
      state = state.copyWith(
        isPurchasing: false,
        balance: currentBalance.copyWith(availableCents: newBalanceCents),
      );

      return result;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Wallet purchase failed',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isPurchasing: false,
        error: appError.userMessage,
      );
      return null;
    }
  }

  /// Clear any error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ============================================================
// PROVIDERS
// ============================================================

final _walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository();
});

/// Main provider for wallet balance state.
final walletBalanceProvider =
    StateNotifierProvider<WalletBalanceNotifier, WalletBalanceState>((ref) {
  final repository = ref.watch(_walletRepositoryProvider);
  return WalletBalanceNotifier(repository);
});

/// Convenience: available balance in cents.
final walletAvailableProvider = Provider<int>((ref) {
  return ref.watch(walletBalanceProvider).availableCents;
});

/// Convenience: whether wallet has sufficient funds.
final hasWalletFundsProvider = Provider<bool>((ref) {
  return ref.watch(walletBalanceProvider).hasFunds;
});

/// Convenience: wallet is loading.
final walletLoadingProvider = Provider<bool>((ref) {
  return ref.watch(walletBalanceProvider).isLoading;
});

/// Convenience: wallet error.
final walletErrorProvider = Provider<String?>((ref) {
  return ref.watch(walletBalanceProvider).error;
});
