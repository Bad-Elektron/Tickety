import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../../../core/state/app_state.dart';
import '../models/subscription.dart';
import 'i_subscription_repository.dart';

const _tag = 'SubscriptionRepository';

/// Supabase implementation of [ISubscriptionRepository].
///
/// Uses Edge Functions for Stripe operations (security)
/// and direct database access for reading subscription records.
class SubscriptionRepository implements ISubscriptionRepository {
  final _client = SupabaseService.instance.client;

  @override
  Future<Subscription?> getMySubscription() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.debug('No current user for subscription', tag: _tag);
      return null;
    }

    AppLogger.info('Fetching subscription for user: $userId', tag: _tag);

    final response = await _client
        .from('subscriptions')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    AppLogger.info('Subscription query response: $response', tag: _tag);

    if (response == null) {
      AppLogger.info('No subscription found for user', tag: _tag);
      return null;
    }

    final subscription = Subscription.fromJson(response);
    AppLogger.info(
      'Found subscription: tier=${subscription.tier}, status=${subscription.status}, stripeId=${subscription.stripeSubscriptionId}',
      tag: _tag,
    );
    return subscription;
  }

  @override
  Future<SubscriptionCheckoutResponse> createCheckout(AccountTier tier) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    if (tier == AccountTier.base) {
      throw SubscriptionException(
        'Cannot checkout for base tier',
        technicalDetails: 'Base tier is free and does not require checkout',
      );
    }

    AppLogger.info(
      'Creating subscription checkout: tier=${tier.name}',
      tag: _tag,
    );

    try {
      AppLogger.debug('Invoking create-subscription-checkout function', tag: _tag);

      final response = await _client.functions.invoke(
        'create-subscription-checkout',
        body: {
          'tier': tier.name,
          'user_id': userId,
        },
      );

      AppLogger.debug(
        'Function response: status=${response.status}, data=${response.data}',
        tag: _tag,
      );

      if (response.status != 200) {
        final error = response.data is Map ? response.data['error'] : response.data?.toString() ?? 'Unknown error';
        AppLogger.error(
          'Failed to create subscription checkout: status=${response.status}, error=$error',
          tag: _tag,
        );
        throw SubscriptionException(
          'Failed to start upgrade: $error',
          technicalDetails: 'Edge function error (${response.status}): $error',
        );
      }

      final data = response.data as Map<String, dynamic>;
      AppLogger.info('Subscription checkout created', tag: _tag);
      return SubscriptionCheckoutResponse.fromJson(data);
    } catch (e, stackTrace) {
      if (e is SubscriptionException) rethrow;
      AppLogger.error(
        'Edge function call failed',
        error: e,
        stackTrace: stackTrace,
        tag: _tag,
      );
      // Show actual error for debugging
      throw SubscriptionException(
        'Upgrade failed: ${e.toString().length > 150 ? e.toString().substring(0, 150) : e}',
        technicalDetails: 'Edge function error: $e',
      );
    }
  }

  @override
  Future<Subscription> cancelSubscription() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info('Canceling subscription for user: $userId', tag: _tag);

    try {
      final response = await _client.functions.invoke(
        'manage-subscription',
        body: {
          'action': 'cancel',
          'user_id': userId,
        },
      );

      AppLogger.info(
        'Cancel response: status=${response.status}, data=${response.data}',
        tag: _tag,
      );

      if (response.status != 200) {
        final error = response.data is Map ? response.data['error'] : 'Unknown error';
        AppLogger.error(
          'Failed to cancel subscription: $error',
          tag: _tag,
        );
        throw SubscriptionException.cancelFailed(error.toString());
      }

      final data = response.data as Map<String, dynamic>;
      AppLogger.info('Subscription canceled successfully', tag: _tag);
      return Subscription.fromJson(data['subscription'] as Map<String, dynamic>);
    } catch (e, stackTrace) {
      if (e is SubscriptionException) rethrow;
      AppLogger.error(
        'Cancel subscription failed',
        error: e,
        stackTrace: stackTrace,
        tag: _tag,
      );
      throw SubscriptionException.cancelFailed(
        e.toString().length > 150 ? e.toString().substring(0, 150) : e.toString(),
      );
    }
  }

  @override
  Future<Subscription> resumeSubscription() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info('Resuming subscription', tag: _tag);

    try {
      final response = await _client.functions.invoke(
        'manage-subscription',
        body: {
          'action': 'resume',
          'user_id': userId,
        },
      );

      if (response.status != 200) {
        final error = response.data is Map ? response.data['error'] : 'Unknown error';
        AppLogger.error(
          'Failed to resume subscription: $error',
          tag: _tag,
        );
        throw SubscriptionException.resumeFailed(error.toString());
      }

      final data = response.data as Map<String, dynamic>;
      AppLogger.info('Subscription resumed successfully', tag: _tag);
      return Subscription.fromJson(data['subscription'] as Map<String, dynamic>);
    } catch (e, stackTrace) {
      if (e is SubscriptionException) rethrow;
      AppLogger.error(
        'Resume subscription failed',
        error: e,
        stackTrace: stackTrace,
        tag: _tag,
      );
      throw SubscriptionException.resumeFailed(
        e.toString().length > 150 ? e.toString().substring(0, 150) : e.toString(),
      );
    }
  }

  @override
  Future<CustomerPortalResponse> getCustomerPortalUrl() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info('Getting customer portal URL', tag: _tag);

    try {
      final response = await _client.functions.invoke(
        'create-customer-portal',
        body: {
          'user_id': userId,
        },
      );

      if (response.status != 200) {
        final error = response.data is Map ? response.data['error'] : 'Unknown error';
        AppLogger.error(
          'Failed to get customer portal URL: $error',
          tag: _tag,
        );
        throw SubscriptionException(
          'Failed to open billing portal: $error',
          technicalDetails: 'Edge function error: $error',
        );
      }

      final data = response.data as Map<String, dynamic>;
      AppLogger.info('Customer portal URL retrieved', tag: _tag);
      return CustomerPortalResponse.fromJson(data);
    } catch (e, stackTrace) {
      if (e is SubscriptionException) rethrow;
      AppLogger.error(
        'Get customer portal URL failed',
        error: e,
        stackTrace: stackTrace,
        tag: _tag,
      );
      throw SubscriptionException(
        'Failed to open billing portal. Please try again.',
        technicalDetails: 'Edge function error: $e',
      );
    }
  }

  @override
  Future<void> verifySubscription(String subscriptionId) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.error('Cannot verify - no user', tag: _tag);
      throw AuthException.notAuthenticated();
    }

    AppLogger.info('=== VERIFYING SUBSCRIPTION ===', tag: _tag);
    AppLogger.info('Subscription ID: $subscriptionId', tag: _tag);
    AppLogger.info('User ID: $userId', tag: _tag);

    try {
      final response = await _client.functions.invoke(
        'verify-subscription',
        body: {
          'subscription_id': subscriptionId,
        },
      );

      AppLogger.info('Verify response status: ${response.status}', tag: _tag);
      AppLogger.info('Verify response data: ${response.data}', tag: _tag);

      if (response.status != 200) {
        final error = response.data is Map ? response.data['error'] : 'Unknown error';
        AppLogger.error(
          'Failed to verify subscription: $error',
          tag: _tag,
        );
        // Don't throw - verification is best-effort
        return;
      }

      AppLogger.info('Subscription verified successfully', tag: _tag);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Subscription verification failed',
        error: e,
        stackTrace: stackTrace,
        tag: _tag,
      );
      // Don't throw - verification is best-effort
    }
  }

  @override
  Future<Subscription> devOverrideTier(AccountTier tier) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info('[DEV] Overriding subscription to ${tier.name}', tag: _tag);

    try {
      final response = await _client.functions.invoke(
        'dev-override-subscription',
        body: {
          'tier': tier.name,
        },
      );

      if (response.status != 200) {
        final error = response.data is Map ? response.data['error'] : 'Unknown error';
        AppLogger.error('[DEV] Override failed: $error', tag: _tag);
        throw SubscriptionException(
          'Dev override failed: $error',
          technicalDetails: 'Edge function error (${response.status}): $error',
        );
      }

      final data = response.data as Map<String, dynamic>;
      AppLogger.info('[DEV] Subscription overridden successfully', tag: _tag);
      return Subscription.fromJson(data['subscription'] as Map<String, dynamic>);
    } catch (e, stackTrace) {
      if (e is SubscriptionException) rethrow;
      AppLogger.error(
        '[DEV] Override failed',
        error: e,
        stackTrace: stackTrace,
        tag: _tag,
      );
      throw SubscriptionException(
        'Dev override failed: ${e.toString().length > 150 ? e.toString().substring(0, 150) : e}',
        technicalDetails: 'Edge function error: $e',
      );
    }
  }
}
