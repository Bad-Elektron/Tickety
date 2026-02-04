import '../../../core/errors/errors.dart';
import '../../../core/models/models.dart';
import '../../../core/services/services.dart';
import '../models/cash_transaction.dart';

const _tag = 'CashTransactionRepository';

/// Result of a cash sale operation.
class CashSaleResult {
  final bool success;
  final String? ticketId;
  final String? ticketNumber;
  final String? cashTransactionId;
  final int? platformFeeCents;
  final bool feeCharged;
  final String? transferToken;
  final DateTime? transferTokenExpiresAt;
  final String? warning;
  final String? error;

  const CashSaleResult({
    required this.success,
    this.ticketId,
    this.ticketNumber,
    this.cashTransactionId,
    this.platformFeeCents,
    this.feeCharged = false,
    this.transferToken,
    this.transferTokenExpiresAt,
    this.warning,
    this.error,
  });

  factory CashSaleResult.fromJson(Map<String, dynamic> json) {
    final ticket = json['ticket'] as Map<String, dynamic>?;
    return CashSaleResult(
      success: json['success'] as bool? ?? false,
      ticketId: ticket?['id'] as String?,
      ticketNumber: ticket?['ticket_number'] as String?,
      cashTransactionId: json['cash_transaction_id'] as String?,
      platformFeeCents: json['platform_fee_cents'] as int?,
      feeCharged: json['fee_charged'] as bool? ?? false,
      transferToken: json['transfer_token'] as String?,
      transferTokenExpiresAt: json['transfer_token_expires_at'] != null
          ? DateTime.parse(json['transfer_token_expires_at'] as String)
          : null,
      warning: json['warning'] as String?,
      error: json['error'] as String?,
    );
  }

  factory CashSaleResult.error(String message) {
    return CashSaleResult(
      success: false,
      error: message,
    );
  }
}

/// Repository for cash transaction operations.
class CashTransactionRepository {
  final _client = SupabaseService.instance.client;

  /// Process a cash sale.
  ///
  /// Calls the `process-cash-sale` edge function which:
  /// 1. Verifies staff has permission for event
  /// 2. Creates ticket with payment_method: 'cash'
  /// 3. Creates cash_transactions record
  /// 4. Charges organizer's card for 5% platform fee
  /// 5. Returns ticket data for delivery
  Future<CashSaleResult> createCashSale({
    required String eventId,
    required int amountCents,
    required CashDeliveryMethod deliveryMethod,
    String? ticketTypeId,
    String? customerName,
    String? customerEmail,
  }) async {
    AppLogger.debug(
      'Processing cash sale: event=$eventId, amount=$amountCents, delivery=${deliveryMethod.value}',
      tag: _tag,
    );

    try {
      final response = await _client.functions.invoke(
        'process-cash-sale',
        body: {
          'event_id': eventId,
          'amount_cents': amountCents,
          'delivery_method': deliveryMethod.value,
          if (ticketTypeId != null) 'ticket_type_id': ticketTypeId,
          if (customerName != null) 'customer_name': customerName,
          if (customerEmail != null) 'customer_email': customerEmail,
        },
      );

      if (response.status != 200) {
        final error = response.data?['error'] as String? ?? 'Unknown error';
        AppLogger.error('Cash sale failed: $error', tag: _tag);
        return CashSaleResult.error(error);
      }

      final result = CashSaleResult.fromJson(
        response.data as Map<String, dynamic>,
      );

      if (result.success) {
        AppLogger.info(
          'Cash sale completed: ticket=${result.ticketNumber}, fee_charged=${result.feeCharged}',
          tag: _tag,
        );
      }

      return result;
    } catch (e, s) {
      AppLogger.error(
        'Cash sale error',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      return CashSaleResult.error(e.toString());
    }
  }

  /// Get cash transactions for the current seller.
  Future<PaginatedResult<CashTransaction>> getSellerCashTransactions({
    String? eventId,
    int page = 0,
    int pageSize = 20,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      return PaginatedResult.empty(pageSize: pageSize);
    }

    AppLogger.debug(
      'Fetching seller cash transactions: userId=$userId, eventId=$eventId',
      tag: _tag,
    );

    final from = page * pageSize;
    final to = from + pageSize;

    // Build filter query first, then apply order
    var filterQuery = _client
        .from('cash_transactions')
        .select('*, tickets(ticket_number)')
        .eq('seller_id', userId);

    if (eventId != null) {
      filterQuery = filterQuery.eq('event_id', eventId);
    }

    final response = await filterQuery
        .order('created_at', ascending: false)
        .range(from, to);

    final allItems = (response as List<dynamic>)
        .map((json) => CashTransaction.fromJson(json as Map<String, dynamic>))
        .toList();

    final hasMore = allItems.length > pageSize;
    final results = hasMore ? allItems.take(pageSize).toList() : allItems;

    AppLogger.debug(
      'Fetched ${results.length} cash transactions (hasMore: $hasMore)',
      tag: _tag,
    );

    return PaginatedResult(
      items: results,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  /// Get all cash transactions for an event (organizer only).
  Future<PaginatedResult<CashTransaction>> getEventCashTransactions({
    required String eventId,
    CashTransactionStatus? status,
    int page = 0,
    int pageSize = 20,
  }) async {
    AppLogger.debug(
      'Fetching event cash transactions: eventId=$eventId, status=$status',
      tag: _tag,
    );

    final from = page * pageSize;
    final to = from + pageSize;

    // Build filter query first, then apply order
    var filterQuery = _client
        .from('cash_transactions')
        .select('*, tickets(ticket_number)')
        .eq('event_id', eventId);

    if (status != null) {
      filterQuery = filterQuery.eq('status', status.value);
    }

    final response = await filterQuery
        .order('created_at', ascending: false)
        .range(from, to);
    final txList = response as List<dynamic>;

    if (txList.isEmpty) {
      return PaginatedResult.empty(pageSize: pageSize);
    }

    // Get seller profiles in a separate query (to get email/name)
    final sellerIds =
        txList.map((tx) => tx['seller_id'] as String).toSet().toList();

    final profilesResponse = await _client
        .from('profiles')
        .select('id, email, display_name')
        .inFilter('id', sellerIds);

    final profilesMap = <String, Map<String, dynamic>>{};
    for (final profile in profilesResponse as List<dynamic>) {
      final profileMap = profile as Map<String, dynamic>;
      profilesMap[profileMap['id'] as String] = profileMap;
    }

    // Merge profile data
    final allItems = txList.map((json) {
      final txJson = Map<String, dynamic>.from(json as Map<String, dynamic>);
      final sellerId = txJson['seller_id'] as String;
      final profile = profilesMap[sellerId];
      if (profile != null) {
        txJson['profiles'] = {
          'email': profile['email'],
          'display_name': profile['display_name'],
        };
      }
      return CashTransaction.fromJson(txJson);
    }).toList();

    final hasMore = allItems.length > pageSize;
    final results = hasMore ? allItems.take(pageSize).toList() : allItems;

    AppLogger.debug(
      'Fetched ${results.length} event cash transactions (hasMore: $hasMore)',
      tag: _tag,
    );

    return PaginatedResult(
      items: results,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  /// Get cash summary for an event.
  Future<CashSummary> getEventCashSummary(String eventId) async {
    AppLogger.debug('Fetching cash summary for event: $eventId', tag: _tag);

    try {
      final response = await _client.rpc(
        'get_event_cash_summary',
        params: {'p_event_id': eventId},
      );

      if (response == null || (response as List).isEmpty) {
        return CashSummary.empty();
      }

      return CashSummary.fromJson(response[0] as Map<String, dynamic>);
    } catch (e, s) {
      AppLogger.error(
        'Failed to get cash summary',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      return CashSummary.empty();
    }
  }

  /// Get cash summary per seller for an event.
  Future<List<SellerCashSummary>> getEventCashBySeller(String eventId) async {
    AppLogger.debug('Fetching cash by seller for event: $eventId', tag: _tag);

    try {
      final response = await _client.rpc(
        'get_event_cash_by_seller',
        params: {'p_event_id': eventId},
      );

      if (response == null) {
        return [];
      }

      return (response as List<dynamic>)
          .map((json) =>
              SellerCashSummary.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, s) {
      AppLogger.error(
        'Failed to get cash by seller',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      return [];
    }
  }

  /// Mark a cash transaction as collected.
  Future<bool> markCollected(String transactionId) async {
    AppLogger.debug('Marking transaction as collected: $transactionId',
        tag: _tag);

    try {
      final userId = SupabaseService.instance.currentUser?.id;

      await _client.from('cash_transactions').update({
        'status': CashTransactionStatus.collected.value,
        'reconciled_at': DateTime.now().toIso8601String(),
        'reconciled_by': userId,
      }).eq('id', transactionId);

      AppLogger.info('Transaction marked as collected: $transactionId',
          tag: _tag);
      return true;
    } catch (e, s) {
      AppLogger.error(
        'Failed to mark transaction as collected',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      return false;
    }
  }

  /// Mark a cash transaction as disputed.
  Future<bool> markDisputed(String transactionId) async {
    AppLogger.debug('Marking transaction as disputed: $transactionId',
        tag: _tag);

    try {
      final userId = SupabaseService.instance.currentUser?.id;

      await _client.from('cash_transactions').update({
        'status': CashTransactionStatus.disputed.value,
        'reconciled_at': DateTime.now().toIso8601String(),
        'reconciled_by': userId,
      }).eq('id', transactionId);

      AppLogger.info('Transaction marked as disputed: $transactionId',
          tag: _tag);
      return true;
    } catch (e, s) {
      AppLogger.error(
        'Failed to mark transaction as disputed',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      return false;
    }
  }

  /// Mark multiple transactions as collected (bulk operation).
  Future<int> markMultipleCollected(List<String> transactionIds) async {
    if (transactionIds.isEmpty) return 0;

    AppLogger.debug(
        'Marking ${transactionIds.length} transactions as collected',
        tag: _tag);

    try {
      final userId = SupabaseService.instance.currentUser?.id;

      await _client.from('cash_transactions').update({
        'status': CashTransactionStatus.collected.value,
        'reconciled_at': DateTime.now().toIso8601String(),
        'reconciled_by': userId,
      }).inFilter('id', transactionIds);

      AppLogger.info(
          '${transactionIds.length} transactions marked as collected',
          tag: _tag);
      return transactionIds.length;
    } catch (e, s) {
      AppLogger.error(
        'Failed to mark transactions as collected',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      return 0;
    }
  }

  /// Check if cash sales are enabled for an event.
  Future<bool> isCashSalesEnabled(String eventId) async {
    try {
      final response = await _client
          .from('events')
          .select('cash_sales_enabled')
          .eq('id', eventId)
          .single();

      return response['cash_sales_enabled'] as bool? ?? false;
    } catch (e) {
      AppLogger.error('Failed to check cash sales status', error: e, tag: _tag);
      return false;
    }
  }

  /// Look up a user by their email address.
  ///
  /// Returns a map with 'id', 'name', and 'email' if found, or null if not.
  Future<Map<String, dynamic>?> lookupUserByEmail(String email) async {
    AppLogger.debug('Looking up user by email: $email', tag: _tag);

    try {
      final response = await _client
          .from('profiles')
          .select('id, email, display_name')
          .eq('email', email.toLowerCase())
          .maybeSingle();

      if (response == null) {
        AppLogger.debug('No user found with email: $email', tag: _tag);
        return null;
      }

      return {
        'id': response['id'] as String,
        'name': response['display_name'] as String? ?? email.split('@').first,
        'email': response['email'] as String,
      };
    } catch (e, s) {
      AppLogger.error(
        'Failed to lookup user by email',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      return null;
    }
  }
}
