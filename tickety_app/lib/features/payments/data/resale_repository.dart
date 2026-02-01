import '../../../core/errors/errors.dart';
import '../../../core/models/models.dart';
import '../../../core/services/services.dart';
import '../models/resale_listing.dart';
import '../models/seller_balance.dart';
import 'i_resale_repository.dart';

const _tag = 'ResaleRepository';

/// Supabase implementation of [IResaleRepository].
class ResaleRepository implements IResaleRepository {
  final _client = SupabaseService.instance.client;

  @override
  Future<int> getResaleListingCount(String eventId) async {
    AppLogger.debug('Fetching resale listing count for event: $eventId', tag: _tag);

    final response = await _client
        .from('resale_listings')
        .select('id, tickets!inner(event_id)')
        .eq('status', 'active')
        .eq('tickets.event_id', eventId)
        .count();

    final count = response.count;
    AppLogger.debug('Found $count active resale listings for event', tag: _tag);
    return count;
  }

  @override
  Future<PaginatedResult<ResaleListing>> getEventListings(
    String eventId, {
    int page = 0,
    int pageSize = 20,
  }) async {
    AppLogger.debug(
      'Fetching resale listings for event: $eventId (page: $page, pageSize: $pageSize)',
      tag: _tag,
    );

    final from = page * pageSize;
    final to = from + pageSize;

    final response = await _client
        .from('resale_listings')
        .select('*, tickets!inner(*, events(*))')
        .eq('status', 'active')
        .eq('tickets.event_id', eventId)
        .order('price_cents', ascending: true)
        .range(from, to);

    final allItems = (response as List<dynamic>)
        .map((json) => ResaleListing.fromJson(json as Map<String, dynamic>))
        .toList();

    final hasMore = allItems.length > pageSize;
    final listings = hasMore ? allItems.take(pageSize).toList() : allItems;

    AppLogger.debug(
      'Found ${listings.length} listings for event (hasMore: $hasMore)',
      tag: _tag,
    );

    return PaginatedResult(
      items: listings,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  @override
  Future<ResaleListing?> getListing(String listingId) async {
    AppLogger.debug('Fetching listing: $listingId', tag: _tag);

    final response = await _client
        .from('resale_listings')
        .select('*, tickets(*, events(*)), profiles(full_name)')
        .eq('id', listingId)
        .maybeSingle();

    if (response == null) {
      AppLogger.debug('Listing not found: $listingId', tag: _tag);
      return null;
    }

    return ResaleListing.fromJson(response);
  }

  @override
  Future<PaginatedResult<ResaleListing>> getMyListings({
    int page = 0,
    int pageSize = 20,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.debug('No current user for listings', tag: _tag);
      return PaginatedResult.empty(pageSize: pageSize);
    }

    AppLogger.debug(
      'Fetching listings for user: $userId (page: $page, pageSize: $pageSize)',
      tag: _tag,
    );

    final from = page * pageSize;
    final to = from + pageSize; // Fetch one extra to check hasMore

    final response = await _client
        .from('resale_listings')
        .select('*, tickets(*, events(*))')
        .eq('seller_id', userId)
        .order('created_at', ascending: false)
        .range(from, to);

    final allItems = (response as List<dynamic>)
        .map((json) => ResaleListing.fromJson(json as Map<String, dynamic>))
        .toList();

    final hasMore = allItems.length > pageSize;
    final listings = hasMore ? allItems.take(pageSize).toList() : allItems;

    AppLogger.debug(
      'Found ${listings.length} user listings (hasMore: $hasMore)',
      tag: _tag,
    );

    return PaginatedResult(
      items: listings,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  @override
  Future<ResaleListing> createListing({
    required String ticketId,
    required int priceCents,
    String currency = 'usd',
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info(
      'Creating resale listing: ticket=$ticketId, price=$priceCents cents',
      tag: _tag,
    );

    // Check if user has a seller account (NOT full onboarding required!)
    // This allows sellers to list immediately; they complete bank setup when withdrawing
    final hasSeller = await hasSellerAccount();
    if (!hasSeller) {
      throw PaymentException.connectAccountRequired();
    }

    final response = await _client
        .from('resale_listings')
        .insert({
          'ticket_id': ticketId,
          'seller_id': userId,
          'price_cents': priceCents,
          'currency': currency,
          'status': 'active',
        })
        .select('*, tickets(*, events(*))')
        .single();

    final listing = ResaleListing.fromJson(response);
    AppLogger.info('Resale listing created: ${listing.id}', tag: _tag);
    return listing;
  }

  @override
  Future<ResaleListing> updateListingPrice(String listingId, int priceCents) async {
    AppLogger.info(
      'Updating listing price: $listingId -> $priceCents cents',
      tag: _tag,
    );

    final response = await _client
        .from('resale_listings')
        .update({'price_cents': priceCents})
        .eq('id', listingId)
        .select('*, tickets(*, events(*))')
        .single();

    final listing = ResaleListing.fromJson(response);
    AppLogger.info('Listing price updated: ${listing.id}', tag: _tag);
    return listing;
  }

  @override
  Future<void> cancelListing(String listingId) async {
    AppLogger.info('Cancelling listing: $listingId', tag: _tag);

    await _client
        .from('resale_listings')
        .update({'status': 'cancelled'})
        .eq('id', listingId);

    AppLogger.info('Listing cancelled: $listingId', tag: _tag);
  }

  @override
  Future<bool> isSellerOnboarded() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return false;

    final response = await _client
        .from('profiles')
        .select('stripe_connect_onboarded')
        .eq('id', userId)
        .single();

    return response['stripe_connect_onboarded'] == true;
  }

  @override
  Future<String> createConnectAccount() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info('Creating Stripe Connect account for user', tag: _tag);

    final response = await _client.functions.invoke(
      'create-connect-account',
      body: {'user_id': userId},
    );

    if (response.status != 200) {
      final error = response.data is Map ? response.data['error'] : 'Unknown error';
      AppLogger.error('Failed to create Connect account: $error', tag: _tag);
      throw PaymentException(
        'Failed to set up seller account. Please try again.',
        technicalDetails: 'Edge function error: $error',
      );
    }

    final data = response.data as Map<String, dynamic>;
    final onboardingUrl = data['onboarding_url'] as String;

    AppLogger.info('Connect account created, onboarding URL generated', tag: _tag);
    return onboardingUrl;
  }

  @override
  Future<bool> checkOnboardingStatus() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return false;

    AppLogger.debug('Checking Connect onboarding status', tag: _tag);

    // Re-fetch the profile to get updated status
    final response = await _client
        .from('profiles')
        .select('stripe_connect_onboarded, stripe_connect_account_id')
        .eq('id', userId)
        .single();

    final isOnboarded = response['stripe_connect_onboarded'] == true;
    AppLogger.debug('Connect onboarding status: $isOnboarded', tag: _tag);
    return isOnboarded;
  }

  // ============================================================
  // NEW WALLET METHODS
  // ============================================================

  @override
  Future<bool> hasSellerAccount() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return false;

    AppLogger.debug('Checking for seller account', tag: _tag);

    // Check seller_balances first (new flow)
    final balanceResponse = await _client
        .from('seller_balances')
        .select('stripe_account_id')
        .eq('user_id', userId)
        .maybeSingle();

    if (balanceResponse != null &&
        balanceResponse['stripe_account_id'] != null) {
      AppLogger.debug('Found seller account in seller_balances', tag: _tag);
      return true;
    }

    // Fall back to profiles (legacy)
    final profileResponse = await _client
        .from('profiles')
        .select('stripe_connect_account_id')
        .eq('id', userId)
        .single();

    final hasAccount = profileResponse['stripe_connect_account_id'] != null;
    AppLogger.debug('Seller account from profiles: $hasAccount', tag: _tag);
    return hasAccount;
  }

  @override
  Future<String> createSellerAccount() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info('Creating seller account for user', tag: _tag);

    final response = await _client.functions.invoke(
      'create-seller-account',
      body: {'user_id': userId},
    );

    if (response.status != 200) {
      final error =
          response.data is Map ? response.data['error'] : 'Unknown error';
      AppLogger.error('Failed to create seller account: $error', tag: _tag);
      throw PaymentException(
        'Failed to set up seller account. Please try again.',
        technicalDetails: 'Edge function error: $error',
      );
    }

    final data = response.data as Map<String, dynamic>;
    final accountId = data['account_id'] as String;
    final alreadyExists = data['already_exists'] as bool? ?? false;

    AppLogger.info(
      'Seller account ${alreadyExists ? "retrieved" : "created"}: $accountId',
      tag: _tag,
    );
    return accountId;
  }

  @override
  Future<SellerBalance> getSellerBalance() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.debug('Fetching seller balance', tag: _tag);

    final response = await _client.functions.invoke(
      'get-seller-balance',
      body: {'user_id': userId},
    );

    if (response.status != 200) {
      final error =
          response.data is Map ? response.data['error'] : 'Unknown error';
      AppLogger.error('Failed to fetch seller balance: $error', tag: _tag);
      throw PaymentException(
        'Failed to load wallet balance. Please try again.',
        technicalDetails: 'Edge function error: $error',
      );
    }

    final data = response.data as Map<String, dynamic>;
    final balance = SellerBalance.fromJson(data);

    AppLogger.debug('Seller balance: $balance', tag: _tag);
    return balance;
  }

  @override
  Future<WithdrawalResult> initiateWithdrawal({int? amountCents}) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info(
      'Initiating withdrawal${amountCents != null ? " for $amountCents cents" : " (full balance)"}',
      tag: _tag,
    );

    final body = <String, dynamic>{'user_id': userId};
    if (amountCents != null) {
      body['amount_cents'] = amountCents;
    }

    final response = await _client.functions.invoke(
      'initiate-withdrawal',
      body: body,
    );

    if (response.status != 200) {
      final error =
          response.data is Map ? response.data['error'] : 'Unknown error';
      AppLogger.error('Failed to initiate withdrawal: $error', tag: _tag);
      throw PaymentException(
        error ?? 'Failed to process withdrawal. Please try again.',
        technicalDetails: 'Edge function error: $error',
      );
    }

    final data = response.data as Map<String, dynamic>;
    final result = WithdrawalResult.fromJson(data);

    AppLogger.info('Withdrawal result: $result', tag: _tag);
    return result;
  }
}
