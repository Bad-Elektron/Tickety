/// Model representing a seller's balance from their Stripe Connect account.
///
/// Funds are held by Stripe (a licensed money transmitter), not by Tickety.
/// This allows sellers to list tickets without completing full bank verification.
class SellerBalance {
  /// Whether the user has a seller account at all.
  final bool hasAccount;

  /// Available balance in cents (can be withdrawn).
  final int availableBalanceCents;

  /// Pending balance in cents (sales being processed).
  final int pendingBalanceCents;

  /// Whether withdrawals are enabled (bank details added).
  final bool payoutsEnabled;

  /// Whether the seller has completed full Stripe verification.
  final bool detailsSubmitted;

  /// Whether the seller needs to complete onboarding to withdraw.
  final bool needsOnboarding;

  /// Currency code (e.g., 'usd').
  final String currency;

  const SellerBalance({
    required this.hasAccount,
    required this.availableBalanceCents,
    required this.pendingBalanceCents,
    required this.payoutsEnabled,
    required this.detailsSubmitted,
    required this.needsOnboarding,
    this.currency = 'usd',
  });

  /// Creates an empty balance for users without a seller account.
  const SellerBalance.empty()
      : hasAccount = false,
        availableBalanceCents = 0,
        pendingBalanceCents = 0,
        payoutsEnabled = false,
        detailsSubmitted = false,
        needsOnboarding = true,
        currency = 'usd';

  factory SellerBalance.fromJson(Map<String, dynamic> json) {
    return SellerBalance(
      hasAccount: json['has_account'] as bool? ?? false,
      availableBalanceCents: json['available_balance_cents'] as int? ?? 0,
      pendingBalanceCents: json['pending_balance_cents'] as int? ?? 0,
      payoutsEnabled: json['payouts_enabled'] as bool? ?? false,
      detailsSubmitted: json['details_submitted'] as bool? ?? false,
      needsOnboarding: json['needs_onboarding'] as bool? ?? true,
      currency: json['currency'] as String? ?? 'usd',
    );
  }

  /// Total balance (available + pending) in cents.
  int get totalBalanceCents => availableBalanceCents + pendingBalanceCents;

  /// Whether there are funds available to withdraw.
  bool get canWithdraw => payoutsEnabled && availableBalanceCents > 0;

  /// Whether there are pending funds.
  bool get hasPendingFunds => pendingBalanceCents > 0;

  /// Whether there are any funds (available or pending).
  bool get hasAnyFunds => totalBalanceCents > 0;

  /// Formatted available balance (e.g., "$12.34").
  String get formattedAvailableBalance {
    final dollars = availableBalanceCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted pending balance (e.g., "$5.00").
  String get formattedPendingBalance {
    final dollars = pendingBalanceCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted total balance (e.g., "$17.34").
  String get formattedTotalBalance {
    final dollars = totalBalanceCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  @override
  String toString() {
    return 'SellerBalance(available: $formattedAvailableBalance, '
        'pending: $formattedPendingBalance, payoutsEnabled: $payoutsEnabled)';
  }
}

/// Result of a withdrawal attempt.
class WithdrawalResult {
  /// Whether the withdrawal was successful.
  final bool success;

  /// Whether the seller needs to complete onboarding first.
  final bool needsOnboarding;

  /// URL to redirect to for completing bank setup (if needsOnboarding).
  final String? onboardingUrl;

  /// Stripe payout ID (if successful).
  final String? payoutId;

  /// Amount withdrawn in cents (if successful).
  final int? amountCents;

  /// Estimated arrival date (if successful).
  final DateTime? estimatedArrival;

  /// Remaining balance after withdrawal (if successful).
  final int? remainingBalanceCents;

  /// Error message (if failed).
  final String? errorMessage;

  const WithdrawalResult({
    required this.success,
    required this.needsOnboarding,
    this.onboardingUrl,
    this.payoutId,
    this.amountCents,
    this.estimatedArrival,
    this.remainingBalanceCents,
    this.errorMessage,
  });

  factory WithdrawalResult.fromJson(Map<String, dynamic> json) {
    return WithdrawalResult(
      success: json['success'] as bool? ?? false,
      needsOnboarding: json['needs_onboarding'] as bool? ?? false,
      onboardingUrl: json['onboarding_url'] as String?,
      payoutId: json['payout_id'] as String?,
      amountCents: json['amount_cents'] as int?,
      estimatedArrival: json['estimated_arrival'] != null
          ? DateTime.parse(json['estimated_arrival'] as String)
          : null,
      remainingBalanceCents: json['remaining_balance_cents'] as int?,
      errorMessage: json['error'] as String? ?? json['message'] as String?,
    );
  }

  /// Formatted withdrawal amount (e.g., "$12.34").
  String? get formattedAmount {
    if (amountCents == null) return null;
    final dollars = amountCents! / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  @override
  String toString() {
    if (success) {
      return 'WithdrawalResult(success, amount: $formattedAmount, payoutId: $payoutId)';
    } else if (needsOnboarding) {
      return 'WithdrawalResult(needsOnboarding)';
    } else {
      return 'WithdrawalResult(failed: $errorMessage)';
    }
  }
}
