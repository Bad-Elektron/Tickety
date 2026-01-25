import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/resale_listing.dart';
import 'i_resale_repository.dart';

const _tag = 'ResaleRepository';

/// Supabase implementation of [IResaleRepository].
class ResaleRepository implements IResaleRepository {
  final _client = SupabaseService.instance.client;

  @override
  Future<List<ResaleListing>> getActiveListings() async {
    AppLogger.debug('Fetching active resale listings', tag: _tag);

    final response = await _client
        .from('resale_listings')
        .select('*, tickets(*, events(*))')
        .eq('status', 'active')
        .order('created_at', ascending: false);

    final listings = (response as List<dynamic>)
        .map((json) => ResaleListing.fromJson(json as Map<String, dynamic>))
        .toList();

    AppLogger.debug('Found ${listings.length} active listings', tag: _tag);
    return listings;
  }

  @override
  Future<List<ResaleListing>> getEventListings(String eventId) async {
    AppLogger.debug('Fetching resale listings for event: $eventId', tag: _tag);

    final response = await _client
        .from('resale_listings')
        .select('*, tickets!inner(*, events(*))')
        .eq('status', 'active')
        .eq('tickets.event_id', eventId)
        .order('price_cents', ascending: true);

    final listings = (response as List<dynamic>)
        .map((json) => ResaleListing.fromJson(json as Map<String, dynamic>))
        .toList();

    AppLogger.debug('Found ${listings.length} listings for event', tag: _tag);
    return listings;
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
  Future<List<ResaleListing>> getMyListings() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.debug('No current user for listings', tag: _tag);
      return [];
    }

    AppLogger.debug('Fetching listings for user: $userId', tag: _tag);

    final response = await _client
        .from('resale_listings')
        .select('*, tickets(*, events(*))')
        .eq('seller_id', userId)
        .order('created_at', ascending: false);

    final listings = (response as List<dynamic>)
        .map((json) => ResaleListing.fromJson(json as Map<String, dynamic>))
        .toList();

    AppLogger.debug('Found ${listings.length} user listings', tag: _tag);
    return listings;
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

    // Check if user has completed Stripe Connect onboarding
    final isOnboarded = await isSellerOnboarded();
    if (!isOnboarded) {
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
}
