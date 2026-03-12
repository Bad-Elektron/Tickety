import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/wallet/data/wallet_pass_repository.dart';
import '../../features/wallet/models/wallet_pass.dart';

/// State for wallet pass operations on a specific ticket.
class WalletPassState {
  final WalletPass? applePass;
  final WalletPass? googlePass;
  final bool isLoading;
  final String? error;

  const WalletPassState({
    this.applePass,
    this.googlePass,
    this.isLoading = false,
    this.error,
  });

  WalletPassState copyWith({
    WalletPass? applePass,
    WalletPass? googlePass,
    bool? isLoading,
    String? error,
  }) {
    return WalletPassState(
      applePass: applePass ?? this.applePass,
      googlePass: googlePass ?? this.googlePass,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Notifier for wallet pass generation and management per ticket.
class WalletPassNotifier extends FamilyNotifier<WalletPassState, String> {
  @override
  WalletPassState build(String arg) {
    return const WalletPassState();
  }

  WalletPassRepository get _repo => ref.read(walletPassRepositoryProvider);

  /// Load existing passes for this ticket.
  Future<void> loadPasses() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final apple = await _repo.getPassForTicket(arg, WalletPassType.apple);
      final google = await _repo.getPassForTicket(arg, WalletPassType.google);
      state = state.copyWith(
        applePass: apple,
        googlePass: google,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Generate a pass and open the URL to add it to the native wallet.
  Future<void> generateAndOpen(WalletPassType passType) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final pass = await _repo.generatePass(arg, passType);

      if (passType == WalletPassType.apple) {
        state = state.copyWith(applePass: pass, isLoading: false);
      } else {
        state = state.copyWith(googlePass: pass, isLoading: false);
      }

      // Open the pass URL
      if (pass.passUrl != null) {
        final uri = Uri.parse(pass.passUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

/// Whether to show Apple Wallet button (iOS only).
bool get showAppleWallet => !kIsWeb && Platform.isIOS;

/// Whether to show Google Wallet button (Android, or web).
bool get showGoogleWallet => kIsWeb || (!kIsWeb && Platform.isAndroid);

/// Provider for wallet pass state per ticket.
final walletPassProvider =
    NotifierProvider.family<WalletPassNotifier, WalletPassState, String>(
  WalletPassNotifier.new,
);

/// Repository provider.
final walletPassRepositoryProvider = Provider<WalletPassRepository>((ref) {
  return WalletPassRepository();
});
