import 'dart:convert';

import '../../../core/errors/errors.dart';
import '../../../core/services/supabase_service.dart';
import '../models/linked_bank_account.dart';
import '../models/wallet_balance.dart';
import '../models/wallet_transaction.dart';

/// Repository for wallet operations (balance, top-up, bank linking, purchases).
class WalletRepository {
  final _client = SupabaseService.instance.client;

  /// Safely parse response.data into a Map, handling String/null cases.
  Map<String, dynamic>? _parseResponse(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (_) {}
    }
    return null;
  }

  // ============================================================
  // BALANCE
  // ============================================================

  /// Get the user's wallet balance and linked bank accounts.
  Future<WalletBalance> getWalletBalance() async {
    final response = await _client.functions.invoke(
      'get-wallet-balance',
    );

    final data = _parseResponse(response.data);
    if (response.status != 200 || data == null) {
      throw PaymentException(
        data?['error'] as String? ?? 'Failed to load wallet balance (status=${response.status})',
      );
    }

    return WalletBalance.fromJson(data);
  }

  // ============================================================
  // BANK ACCOUNT LINKING
  // ============================================================

  /// Create a SetupIntent for linking a bank account via Financial Connections.
  /// Returns client_secret, customer_id, ephemeral_key.
  Future<Map<String, dynamic>> linkBankAccount() async {
    final response = await _client.functions.invoke(
      'link-bank-account',
    );

    final data = _parseResponse(response.data);
    if (response.status != 200 || data == null) {
      throw PaymentException(
        data?['error'] as String? ?? 'Failed to link bank account (status=${response.status})',
      );
    }

    return data;
  }

  /// Save a linked bank account after successful SetupIntent confirmation.
  ///
  /// Pass [paymentMethodId] if available from the client, or [setupIntentId]
  /// to let the server resolve the payment method from Stripe.
  Future<LinkedBankAccount> saveBankAccount({
    String? paymentMethodId,
    String? setupIntentId,
    String? bankName,
    String? last4,
    String? accountType,
  }) async {
    final response = await _client.functions.invoke(
      'manage-bank-accounts',
      body: {
        'action': 'save',
        if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
        if (setupIntentId != null) 'setup_intent_id': setupIntentId,
        if (bankName != null) 'bank_name': bankName,
        if (last4 != null) 'last4': last4,
        if (accountType != null) 'account_type': accountType,
      },
    );

    final data = _parseResponse(response.data);
    if (response.status != 200 || data == null) {
      throw PaymentException(
        data?['error'] as String? ?? 'Failed to save bank account (status=${response.status})',
      );
    }

    final bankData = data['bank_account'];
    if (bankData is! Map<String, dynamic>) {
      throw PaymentException(
        'Unexpected response: bank_account=${bankData.runtimeType}',
      );
    }
    return LinkedBankAccount.fromJson(bankData);
  }

  /// Get the user's linked bank accounts.
  Future<List<LinkedBankAccount>> getBankAccounts() async {
    final response = await _client.functions.invoke(
      'manage-bank-accounts',
      body: {'action': 'list'},
    );

    final data = _parseResponse(response.data);
    if (response.status != 200 || data == null) {
      throw PaymentException(
        data?['error'] as String? ?? 'Failed to load bank accounts (status=${response.status})',
      );
    }

    final accounts = data['bank_accounts'] as List<dynamic>? ?? [];
    return accounts
        .whereType<Map<String, dynamic>>()
        .map((a) => LinkedBankAccount.fromJson(a))
        .toList();
  }

  /// Remove a linked bank account.
  Future<void> removeBankAccount(String paymentMethodId) async {
    final response = await _client.functions.invoke(
      'manage-bank-accounts',
      body: {
        'action': 'remove',
        'payment_method_id': paymentMethodId,
      },
    );

    if (response.status != 200) {
      final data = _parseResponse(response.data);
      throw PaymentException(
        data?['error'] as String? ?? 'Failed to remove bank account (status=${response.status})',
      );
    }
  }

  // ============================================================
  // TOP-UP (ACH)
  // ============================================================

  /// Create an ACH top-up to add funds to the wallet.
  Future<Map<String, dynamic>> createWalletTopUp({
    required int amountCents,
    required String paymentMethodId,
  }) async {
    final response = await _client.functions.invoke(
      'create-wallet-top-up',
      body: {
        'amount_cents': amountCents,
        'payment_method_id': paymentMethodId,
      },
    );

    final topUpData = _parseResponse(response.data);
    if (response.status != 200 || topUpData == null) {
      throw PaymentException(
        topUpData?['error'] as String? ?? 'Failed to create top-up (status=${response.status})',
      );
    }

    return topUpData;
  }

  // ============================================================
  // WALLET PURCHASE
  // ============================================================

  /// Purchase tickets from wallet balance (no Stripe involved).
  Future<Map<String, dynamic>> purchaseFromWallet({
    required String eventId,
    required int quantity,
  }) async {
    final response = await _client.functions.invoke(
      'purchase-from-wallet',
      body: {
        'event_id': eventId,
        'quantity': quantity,
      },
    );

    final purchaseData = _parseResponse(response.data);
    if (response.status != 200 || purchaseData == null) {
      throw PaymentException(
        purchaseData?['error'] as String? ?? 'Wallet purchase failed (status=${response.status})',
      );
    }

    return purchaseData;
  }

  // ============================================================
  // ACH DIRECT PURCHASE
  // ============================================================

  /// Purchase tickets directly via ACH bank transfer.
  /// Tickets are issued immediately; ACH settles in 4-5 business days.
  Future<Map<String, dynamic>> purchaseWithBank({
    required String eventId,
    required int quantity,
    required String paymentMethodId,
    required int amountCents,
    String? promoCodeId,
    List<Map<String, dynamic>>? seatSelections,
  }) async {
    final response = await _client.functions.invoke(
      'create-ach-payment-intent',
      body: {
        'event_id': eventId,
        'quantity': quantity,
        'payment_method_id': paymentMethodId,
        'amount_cents': amountCents,
        if (promoCodeId != null) 'promo_code_id': promoCodeId,
        if (seatSelections != null) 'seat_selections': seatSelections,
      },
    );

    final data = _parseResponse(response.data);
    if (response.status != 200 || data == null) {
      throw PaymentException(
        data?['error'] as String? ??
            'ACH purchase failed (status=${response.status})',
      );
    }

    return data;
  }

  // ============================================================
  // TRANSACTIONS
  // ============================================================

  /// Get wallet transaction history.
  Future<List<WalletTransaction>> getWalletTransactions({
    int page = 0,
    int pageSize = 25,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;

    final response = await _client
        .from('wallet_transactions')
        .select()
        .order('created_at', ascending: false)
        .range(from, to);

    return (response as List<dynamic>)
        .map((row) => WalletTransaction.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
