import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/subscriptions/data/i_subscription_repository.dart';
import '../../features/subscriptions/data/subscription_repository.dart';
import '../../features/subscriptions/models/subscription.dart';
import '../errors/errors.dart';
import '../state/app_state.dart';
import 'auth_provider.dart';

const _tag = 'SubscriptionProvider';

/// State for subscription management.
class SubscriptionState {
  final Subscription? subscription;
  final bool isLoading;
  final String? error;

  const SubscriptionState({
    this.subscription,
    this.isLoading = false,
    this.error,
  });

  SubscriptionState copyWith({
    Subscription? subscription,
    bool? isLoading,
    String? error,
    bool clearSubscription = false,
    bool clearError = false,
  }) {
    return SubscriptionState(
      subscription: clearSubscription ? null : (subscription ?? this.subscription),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// The effective tier - uses subscription tier if active, otherwise base.
  AccountTier get effectiveTier {
    if (subscription == null) return AccountTier.base;
    // Only return the tier if the subscription status grants access
    if (subscription!.status.grantsAccess) {
      return subscription!.tier;
    }
    return AccountTier.base;
  }

  /// Whether the user has an active subscription.
  bool get isActive => subscription?.isActive ?? false;

  /// Whether the subscription will renew.
  bool get willRenew => subscription?.willRenew ?? false;

  /// Whether this is a paid tier.
  bool get isPaid => subscription?.isPaid ?? false;

  /// Days remaining in current period.
  int? get daysRemaining => subscription?.daysRemaining;

  /// Whether the subscription is scheduled for cancellation.
  bool get isCanceling => subscription?.cancelAtPeriodEnd ?? false;
}

/// Notifier for managing subscriptions.
class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  final ISubscriptionRepository _repository;
  final Ref _ref;

  SubscriptionNotifier(this._repository, this._ref)
      : super(const SubscriptionState()) {
    // Listen to auth changes and load subscription when user signs in
    _ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.isAuthenticated != true && next.isAuthenticated) {
        load();
      } else if (previous?.isAuthenticated == true && !next.isAuthenticated) {
        // User signed out, clear subscription
        state = const SubscriptionState();
        _syncWithAppState(AccountTier.base);
      }
    });

    // Load immediately if user is already authenticated
    if (_ref.read(authProvider).isAuthenticated) {
      load();
    }
  }

  /// Load the current user's subscription.
  Future<void> load() async {
    if (state.isLoading) return;

    AppLogger.debug('Loading subscription', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final subscription = await _repository.getMySubscription();

      AppLogger.info(
        'Subscription loaded: ${subscription?.tier.name ?? 'none'}',
        tag: _tag,
      );

      state = state.copyWith(
        subscription: subscription,
        isLoading: false,
        clearSubscription: subscription == null,
      );

      // Sync with AppState for backward compatibility
      _syncWithAppState(subscription?.tier ?? AccountTier.base);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load subscription',
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

  /// Start the upgrade process for a new tier.
  ///
  /// Returns the checkout response data needed to present the payment sheet.
  Future<SubscriptionCheckoutResponse?> startUpgrade(AccountTier tier) async {
    if (tier == AccountTier.base) {
      AppLogger.warning('Cannot upgrade to base tier', tag: _tag);
      return null;
    }

    AppLogger.info('Starting upgrade to ${tier.name}', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final checkoutResponse = await _repository.createCheckout(tier);

      AppLogger.info('Checkout session created', tag: _tag);
      state = state.copyWith(isLoading: false);

      return checkoutResponse;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to start upgrade',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
      return null;
    }
  }

  /// Cancel the current subscription at period end.
  Future<bool> cancel() async {
    AppLogger.info('Canceling subscription', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final updatedSubscription = await _repository.cancelSubscription();

      AppLogger.info('Subscription canceled', tag: _tag);
      state = state.copyWith(
        subscription: updatedSubscription,
        isLoading: false,
      );

      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to cancel subscription',
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

  /// Resume a subscription that was scheduled for cancellation.
  Future<bool> resume() async {
    AppLogger.info('Resuming subscription', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final updatedSubscription = await _repository.resumeSubscription();

      AppLogger.info('Subscription resumed', tag: _tag);
      state = state.copyWith(
        subscription: updatedSubscription,
        isLoading: false,
      );

      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to resume subscription',
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

  /// Refresh subscription after a successful payment.
  ///
  /// If [subscriptionId] is provided, verifies the subscription with Stripe
  /// to ensure the database is updated.
  Future<void> refreshAfterPayment({String? subscriptionId}) async {
    AppLogger.debug('Refreshing subscription after payment', tag: _tag);

    // If we have the subscription ID, verify it directly with Stripe
    if (subscriptionId != null) {
      AppLogger.debug('Verifying subscription: $subscriptionId', tag: _tag);
      await _repository.verifySubscription(subscriptionId);
    } else {
      // Add a small delay to allow webhook to process
      await Future.delayed(const Duration(seconds: 2));
    }

    await load();
  }

  /// [Dev only] Override subscription tier directly via edge function.
  ///
  /// Returns true if successful, false otherwise.
  Future<bool> devOverrideTier(AccountTier tier) async {
    AppLogger.info('[DEV] Overriding tier to ${tier.name}', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final updatedSubscription = await _repository.devOverrideTier(tier);

      AppLogger.info('[DEV] Tier overridden to ${updatedSubscription.tier.name}', tag: _tag);
      state = state.copyWith(
        subscription: updatedSubscription,
        isLoading: false,
      );

      _syncWithAppState(updatedSubscription.tier);
      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        '[DEV] Failed to override tier',
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

  /// Clear any error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Sync the subscription tier with AppState for backward compatibility.
  void _syncWithAppState(AccountTier tier) {
    AppState().tier = tier;
  }
}

// ============================================================
// PROVIDERS
// ============================================================

/// Repository provider - can be overridden for testing.
final subscriptionRepositoryProvider = Provider<ISubscriptionRepository>((ref) {
  return SubscriptionRepository();
});

/// Main subscription provider.
final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  final repository = ref.watch(subscriptionRepositoryProvider);
  return SubscriptionNotifier(repository, ref);
});

/// Convenience provider for the current tier.
final currentTierProvider = Provider<AccountTier>((ref) {
  return ref.watch(subscriptionProvider).effectiveTier;
});

/// Convenience provider for checking Pro access.
final hasProAccessProvider = Provider<bool>((ref) {
  final tier = ref.watch(currentTierProvider);
  return tier == AccountTier.pro || tier == AccountTier.enterprise;
});

/// Convenience provider for checking Enterprise access.
final hasEnterpriseAccessProvider = Provider<bool>((ref) {
  return ref.watch(currentTierProvider) == AccountTier.enterprise;
});

/// Convenience provider for subscription loading state.
final subscriptionLoadingProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionProvider).isLoading;
});

/// Convenience provider for subscription error.
final subscriptionErrorProvider = Provider<String?>((ref) {
  return ref.watch(subscriptionProvider).error;
});
