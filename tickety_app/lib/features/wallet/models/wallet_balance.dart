import 'linked_bank_account.dart';

/// Represents the user's Tickety Wallet balance.
class WalletBalance {
  final int availableCents;
  final int pendingCents;
  final String currency;
  final bool hasLinkedBank;
  final List<LinkedBankAccount> bankAccounts;

  const WalletBalance({
    required this.availableCents,
    required this.pendingCents,
    this.currency = 'usd',
    this.hasLinkedBank = false,
    this.bankAccounts = const [],
  });

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    final accounts = (json['bank_accounts'] as List<dynamic>?)
            ?.map((a) => LinkedBankAccount.fromJson(a as Map<String, dynamic>))
            .toList() ??
        [];

    return WalletBalance(
      availableCents: json['available_cents'] as int? ?? 0,
      pendingCents: json['pending_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'usd',
      hasLinkedBank: json['has_linked_bank'] as bool? ?? accounts.isNotEmpty,
      bankAccounts: accounts,
    );
  }

  /// Empty wallet with no funds.
  const WalletBalance.empty()
      : availableCents = 0,
        pendingCents = 0,
        currency = 'usd',
        hasLinkedBank = false,
        bankAccounts = const [];

  /// Total cents (available + pending).
  int get totalCents => availableCents + pendingCents;

  /// Whether the wallet has any spendable funds.
  bool get hasFunds => availableCents > 0;

  /// Whether the wallet has any pending funds.
  bool get hasPending => pendingCents > 0;

  /// Formatted available balance (e.g., "$50.00").
  String get formattedAvailable {
    final dollars = availableCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted pending balance.
  String get formattedPending {
    final dollars = pendingCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// Formatted total balance.
  String get formattedTotal {
    final dollars = totalCents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  /// The default bank account, if any.
  LinkedBankAccount? get defaultBank {
    final defaults = bankAccounts.where((a) => a.isDefault);
    return defaults.isNotEmpty ? defaults.first : bankAccounts.firstOrNull;
  }

  WalletBalance copyWith({
    int? availableCents,
    int? pendingCents,
    String? currency,
    bool? hasLinkedBank,
    List<LinkedBankAccount>? bankAccounts,
  }) {
    return WalletBalance(
      availableCents: availableCents ?? this.availableCents,
      pendingCents: pendingCents ?? this.pendingCents,
      currency: currency ?? this.currency,
      hasLinkedBank: hasLinkedBank ?? this.hasLinkedBank,
      bankAccounts: bankAccounts ?? this.bankAccounts,
    );
  }

  @override
  String toString() =>
      'WalletBalance(available: $formattedAvailable, pending: $formattedPending)';
}
