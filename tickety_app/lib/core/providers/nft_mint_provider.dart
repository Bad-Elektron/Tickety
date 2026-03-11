import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/wallet/data/cardano_repository.dart';
import '../../features/wallet/models/nft_ticket.dart';

/// State for NFT ticket minting and collection.
class NftMintState {
  final List<NftTicket> nfts;
  final bool isLoading;
  final String? error;

  const NftMintState({
    this.nfts = const [],
    this.isLoading = false,
    this.error,
  });

  NftMintState copyWith({
    List<NftTicket>? nfts,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return NftMintState(
      nfts: nfts ?? this.nfts,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Manages NFT ticket collection from the user's Cardano wallet.
class NftMintNotifier extends StateNotifier<NftMintState> {
  final CardanoRepository _repo;

  NftMintNotifier({CardanoRepository? repo})
      : _repo = repo ?? CardanoRepository(),
        super(const NftMintState());

  /// Load NFT tickets from the user's Cardano wallet.
  Future<void> loadNfts() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final nfts = await _repo.getTicketNfts();
      state = state.copyWith(nfts: nfts, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Poll the mint queue for a specific ticket until it's minted or failed.
  Future<String?> pollMintStatus(String ticketId, {Duration timeout = const Duration(minutes: 5)}) async {
    final supabase = Supabase.instance.client;
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final response = await supabase
          .from('nft_mint_queue')
          .select('status, tx_hash, error_message')
          .eq('ticket_id', ticketId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      final status = response['status'] as String?;
      if (status == 'minted') {
        // Refresh NFT list
        await loadNfts();
        return response['tx_hash'] as String?;
      }
      if (status == 'failed') {
        throw Exception(response['error_message'] ?? 'NFT minting failed');
      }
      if (status == 'skipped') return null;

      await Future.delayed(const Duration(seconds: 5));
    }

    return null; // Timeout
  }

  /// Get the mint queue status for a ticket.
  Future<Map<String, dynamic>?> getMintStatus(String ticketId) async {
    final supabase = Supabase.instance.client;
    return await supabase
        .from('nft_mint_queue')
        .select('status, tx_hash, policy_id, user_asset_id, error_message')
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }
}

/// Provider for NFT mint state.
final nftMintProvider =
    StateNotifierProvider<NftMintNotifier, NftMintState>((ref) {
  return NftMintNotifier();
});

/// Convenience: just the NFT list.
final nftTicketsProvider = Provider<List<NftTicket>>((ref) {
  return ref.watch(nftMintProvider).nfts;
});
