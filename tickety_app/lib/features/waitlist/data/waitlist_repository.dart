import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/waitlist_entry.dart';

class WaitlistRepository {
  final _client = SupabaseService.instance.client;

  /// Get the current user's active waitlist entry for an event (if any).
  Future<WaitlistEntry?> getMyEntry(String eventId) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return null;

    final response = await _client
        .from('waitlist_entries')
        .select()
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    if (response == null) return null;
    return WaitlistEntry.fromJson(response);
  }

  /// Join waitlist in "notify me" mode.
  Future<WaitlistEntry> joinNotify(String eventId) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) throw AuthException.notAuthenticated();

    final response = await _client
        .from('waitlist_entries')
        .insert({
          'event_id': eventId,
          'user_id': userId,
          'mode': 'notify',
        })
        .select()
        .single();

    return WaitlistEntry.fromJson(response);
  }

  /// Join waitlist in "auto-buy" mode with a max price and payment method.
  Future<WaitlistEntry> joinAutoBuy({
    required String eventId,
    required int maxPriceCents,
    required String paymentMethodId,
    required String stripeCustomerId,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) throw AuthException.notAuthenticated();

    final response = await _client
        .from('waitlist_entries')
        .insert({
          'event_id': eventId,
          'user_id': userId,
          'mode': 'auto_buy',
          'max_price_cents': maxPriceCents,
          'payment_method_id': paymentMethodId,
          'stripe_customer_id': stripeCustomerId,
        })
        .select()
        .single();

    return WaitlistEntry.fromJson(response);
  }

  /// Cancel (leave) the waitlist.
  Future<void> cancel(String entryId) async {
    await _client
        .from('waitlist_entries')
        .update({'status': 'cancelled'})
        .eq('id', entryId);
  }

  /// Get waitlist count for an event.
  Future<WaitlistCount> getWaitlistCount(String eventId) async {
    final response = await _client.rpc(
      'get_waitlist_count',
      params: {'p_event_id': eventId},
    );

    if (response is Map<String, dynamic>) {
      return WaitlistCount.fromJson(response);
    }
    return const WaitlistCount();
  }

  /// Get the user's position in the waitlist queue.
  Future<int?> getPosition(String eventId) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return null;

    // Count entries created before the user's entry
    final entry = await getMyEntry(eventId);
    if (entry == null) return null;

    final response = await _client
        .from('waitlist_entries')
        .select('id')
        .eq('event_id', eventId)
        .eq('status', 'active')
        .lte('created_at', entry.createdAt.toIso8601String());

    return (response as List).length;
  }

  /// Fire-and-forget: trigger waitlist processing for an event.
  Future<void> triggerProcessing({
    required String eventId,
    required String trigger,
    String? listingId,
    int? listingPriceCents,
  }) async {
    try {
      await _client.functions.invoke(
        'process-waitlist',
        body: {
          'event_id': eventId,
          'trigger': trigger,
          if (listingId != null) 'listing_id': listingId,
          if (listingPriceCents != null)
            'listing_price_cents': listingPriceCents,
        },
      );
    } catch (e) {
      // Fire-and-forget — log but don't throw
      AppLogger.error(
        'Failed to trigger waitlist processing: $e',
        tag: 'WaitlistRepository',
      );
    }
  }
}
