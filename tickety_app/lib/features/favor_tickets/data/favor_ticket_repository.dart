import '../../../core/errors/errors.dart';
import '../../../core/models/models.dart';
import '../../../core/services/services.dart';
import '../models/ticket_offer.dart';

const _tag = 'FavorTicketRepository';

/// Repository for managing favor/comp ticket offers.
class FavorTicketRepository {
  final _client = SupabaseService.instance.client;

  /// Create a new ticket offer.
  Future<TicketOffer> createOffer({
    required String eventId,
    required String recipientEmail,
    required int priceCents,
    required TicketMode ticketMode,
    String? message,
    String? ticketTypeId,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info(
      'Creating ticket offer: event=$eventId, recipient=$recipientEmail, price=$priceCents, mode=${ticketMode.value}',
      tag: _tag,
    );

    final response = await _client
        .from('ticket_offers')
        .insert({
          'event_id': eventId,
          'organizer_id': userId,
          'recipient_email': recipientEmail.trim().toLowerCase(),
          'price_cents': priceCents,
          'ticket_mode': ticketMode.value,
          if (message != null && message.isNotEmpty) 'message': message,
          if (ticketTypeId != null) 'ticket_type_id': ticketTypeId,
        })
        .select('*, events(title)')
        .single();

    final offer = TicketOffer.fromJson(response);
    AppLogger.info('Ticket offer created: ${offer.id}', tag: _tag);
    return offer;
  }

  /// Fetch a single offer with event and organizer details.
  Future<TicketOffer?> getOffer(String offerId) async {
    AppLogger.debug('Fetching offer: $offerId', tag: _tag);

    final response = await _client
        .from('ticket_offers')
        .select('*, events(title)')
        .eq('id', offerId)
        .maybeSingle();

    if (response == null) return null;

    // Fetch organizer display name separately (no FK to profiles)
    final organizerId = response['organizer_id'] as String?;
    String? organizerName;
    if (organizerId != null) {
      final profile = await _client
          .from('profiles')
          .select('display_name')
          .eq('id', organizerId)
          .maybeSingle();
      organizerName = profile?['display_name'] as String?;
    }

    final enriched = {
      ...response,
      if (organizerName != null) '_organizer_name': organizerName,
    };

    return TicketOffer.fromJson(enriched);
  }

  /// Get pending offers where the current user is the recipient.
  Future<List<TicketOffer>> getMyPendingOffers() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return [];

    AppLogger.debug('Fetching pending offers for user', tag: _tag);

    final response = await _client
        .from('ticket_offers')
        .select('*, events(title)')
        .eq('status', 'pending')
        .or('recipient_user_id.eq.$userId,recipient_email.eq.${SupabaseService.instance.currentUser?.email}')
        .order('created_at', ascending: false);

    final rawOffers = response as List<dynamic>;

    // Fetch organizer names for all unique organizer IDs
    final organizerIds = rawOffers
        .map((o) => (o as Map<String, dynamic>)['organizer_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    final nameMap = <String, String>{};
    if (organizerIds.isNotEmpty) {
      final profiles = await _client
          .from('profiles')
          .select('id, display_name')
          .inFilter('id', organizerIds);
      for (final p in profiles as List<dynamic>) {
        final m = p as Map<String, dynamic>;
        nameMap[m['id'] as String] = m['display_name'] as String? ?? 'Unknown';
      }
    }

    final offers = rawOffers.map((json) {
      final m = json as Map<String, dynamic>;
      final orgId = m['organizer_id'] as String?;
      return TicketOffer.fromJson({
        ...m,
        if (orgId != null && nameMap.containsKey(orgId))
          '_organizer_name': nameMap[orgId],
      });
    }).toList();

    AppLogger.debug('Found ${offers.length} pending offers', tag: _tag);
    return offers;
  }

  /// Get offers sent by the organizer for a specific event (paginated).
  Future<PaginatedResult<TicketOffer>> getSentOffers(
    String eventId, {
    int page = 0,
    int pageSize = 20,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      return PaginatedResult.empty(pageSize: pageSize);
    }

    AppLogger.debug(
      'Fetching sent offers for event: $eventId (page: $page)',
      tag: _tag,
    );

    final from = page * pageSize;
    final to = from + pageSize;

    final response = await _client
        .from('ticket_offers')
        .select('*, events(title)')
        .eq('organizer_id', userId)
        .eq('event_id', eventId)
        .order('created_at', ascending: false)
        .range(from, to);

    final allItems = (response as List<dynamic>)
        .map((json) => TicketOffer.fromJson(json as Map<String, dynamic>))
        .toList();

    final hasMore = allItems.length > pageSize;
    final offers = hasMore ? allItems.take(pageSize).toList() : allItems;

    return PaginatedResult(
      items: offers,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  /// Claim a free offer (calls edge function).
  Future<Map<String, dynamic>> claimFreeOffer(
    String offerId, {
    bool skipMintingFee = false,
  }) async {
    AppLogger.info(
      'Claiming free offer: $offerId (skipMintingFee: $skipMintingFee)',
      tag: _tag,
    );

    final response = await _client.functions.invoke(
      'claim-favor-offer',
      body: {
        'offer_id': offerId,
        if (skipMintingFee) 'skip_minting_fee': true,
      },
    );

    if (response.status != 200) {
      final error = response.data is Map
          ? response.data['error'] as String?
          : 'Failed to claim offer';
      AppLogger.error('Failed to claim offer: $error', tag: _tag);
      throw BusinessException(
        error ?? 'Failed to claim offer. Please try again.',
        technicalDetails: 'Edge function error: $error',
      );
    }

    final data = response.data as Map<String, dynamic>;
    AppLogger.info('Offer claimed successfully', tag: _tag);
    return data;
  }

  /// Decline an offer.
  Future<void> declineOffer(String offerId) async {
    AppLogger.info('Declining offer: $offerId', tag: _tag);

    await _client
        .from('ticket_offers')
        .update({'status': 'declined'})
        .eq('id', offerId);

    AppLogger.info('Offer declined: $offerId', tag: _tag);
  }

  /// Cancel an offer (organizer action).
  Future<void> cancelOffer(String offerId) async {
    AppLogger.info('Cancelling offer: $offerId', tag: _tag);

    await _client
        .from('ticket_offers')
        .update({'status': 'cancelled'})
        .eq('id', offerId);

    AppLogger.info('Offer cancelled: $offerId', tag: _tag);
  }
}
