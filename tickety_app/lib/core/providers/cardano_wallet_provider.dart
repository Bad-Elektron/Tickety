import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/wallet/data/cardano_repository.dart';
import '../../features/wallet/models/cardano_balance.dart';
import '../../features/wallet/models/cardano_transaction.dart';
import '../errors/errors.dart';

const _tag = 'CardanoWalletProvider';

/// State for the Cardano wallet.
class CardanoWalletState {
  final bool hasWallet;
  final String? address;
  final CardanoBalance? balance;
  final List<CardanoTransaction> transactions;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final int currentPage;
  final bool hasMoreTx;

  const CardanoWalletState({
    this.hasWallet = false,
    this.address,
    this.balance,
    this.transactions = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.currentPage = 1,
    this.hasMoreTx = true,
  });

  CardanoWalletState copyWith({
    bool? hasWallet,
    String? address,
    CardanoBalance? balance,
    List<CardanoTransaction>? transactions,
    bool? isLoading,
    bool? isSending,
    String? error,
    bool clearError = false,
    int? currentPage,
    bool? hasMoreTx,
  }) {
    return CardanoWalletState(
      hasWallet: hasWallet ?? this.hasWallet,
      address: address ?? this.address,
      balance: balance ?? this.balance,
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      hasMoreTx: hasMoreTx ?? this.hasMoreTx,
    );
  }
}

/// Notifier for managing Cardano wallet state.
class CardanoWalletNotifier extends StateNotifier<CardanoWalletState> {
  final CardanoRepository _repository;

  CardanoWalletNotifier(this._repository) : super(const CardanoWalletState());

  /// Ensure a wallet exists (local → Supabase → generate new).
  /// Called lazily from wallet screen initState.
  Future<void> ensureWallet() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final address = await _repository.ensureWallet();
      AppLogger.info('Wallet ready: $address', tag: _tag);
      state = state.copyWith(
        hasWallet: true,
        address: address,
        isLoading: false,
      );
      // Kick off balance load
      loadBalance();
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error('Failed to ensure wallet', error: e, stackTrace: s, tag: _tag);
      state = state.copyWith(isLoading: false, error: appError.userMessage);
    }
  }

  /// Load balance from Blockfrost.
  Future<void> loadBalance() async {
    if (!state.hasWallet) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final balance = await _repository.getBalance();
      state = state.copyWith(balance: balance, isLoading: false);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error('Failed to load Cardano balance', error: e, stackTrace: s, tag: _tag);
      state = state.copyWith(isLoading: false, error: appError.userMessage);
    }
  }

  /// Load transaction history (first page).
  Future<void> loadTransactions() async {
    if (!state.hasWallet) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final txs = await _repository.getTransactions(page: 1);
      state = state.copyWith(
        transactions: txs,
        isLoading: false,
        currentPage: 1,
        hasMoreTx: txs.length >= 20,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error('Failed to load Cardano txs', error: e, stackTrace: s, tag: _tag);
      state = state.copyWith(isLoading: false, error: appError.userMessage);
    }
  }

  /// Load more transactions (next page).
  Future<void> loadMoreTransactions() async {
    if (!state.hasMoreTx || state.isLoading) return;
    final nextPage = state.currentPage + 1;
    try {
      final txs = await _repository.getTransactions(page: nextPage);
      state = state.copyWith(
        transactions: [...state.transactions, ...txs],
        currentPage: nextPage,
        hasMoreTx: txs.length >= 20,
      );
    } catch (e, s) {
      AppLogger.error('Failed to load more Cardano txs', error: e, stackTrace: s, tag: _tag);
    }
  }

  /// Send ADA. Returns tx hash on success, null on failure.
  Future<String?> sendAda(String toAddress, int lovelaceAmount) async {
    if (state.isSending) return null;
    state = state.copyWith(isSending: true, clearError: true);
    try {
      final txHash = await _repository.sendAda(toAddress, lovelaceAmount);
      AppLogger.info('Sent ADA: $txHash', tag: _tag);

      // Optimistically update balance
      final currentLovelace = state.balance?.lovelace ?? 0;
      final newLovelace = currentLovelace - lovelaceAmount - 200000; // ~0.2 ADA fee
      state = state.copyWith(
        isSending: false,
        balance: CardanoBalance(
          lovelace: newLovelace.clamp(0, currentLovelace),
          assets: state.balance?.assets ?? [],
        ),
      );
      return txHash;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error('Failed to send ADA', error: e, stackTrace: s, tag: _tag);
      state = state.copyWith(isSending: false, error: appError.userMessage);
      return null;
    }
  }

  /// Refresh balance and transactions.
  Future<void> refresh() async {
    await Future.wait([loadBalance(), loadTransactions()]);
  }

  /// Delete wallet and reset state.
  Future<void> deleteWallet() async {
    await _repository.deleteWallet();
    state = const CardanoWalletState();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ============================================================
// PROVIDERS
// ============================================================

final _cardanoRepositoryProvider = Provider<CardanoRepository>((ref) {
  return CardanoRepository();
});

/// Main provider for Cardano wallet state.
final cardanoWalletProvider =
    StateNotifierProvider<CardanoWalletNotifier, CardanoWalletState>((ref) {
  final repository = ref.watch(_cardanoRepositoryProvider);
  return CardanoWalletNotifier(repository);
});

/// Convenience: Cardano balance.
final cardanoBalanceProvider = Provider<CardanoBalance?>((ref) {
  return ref.watch(cardanoWalletProvider).balance;
});

/// Convenience: Cardano address.
final cardanoAddressProvider = Provider<String?>((ref) {
  return ref.watch(cardanoWalletProvider).address;
});

/// Convenience: whether a Cardano wallet exists.
final cardanoHasWalletProvider = Provider<bool>((ref) {
  return ref.watch(cardanoWalletProvider).hasWallet;
});

/// Convenience: Cardano transactions list.
final cardanoTransactionsProvider = Provider<List<CardanoTransaction>>((ref) {
  return ref.watch(cardanoWalletProvider).transactions;
});
