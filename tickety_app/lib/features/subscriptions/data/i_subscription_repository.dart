import '../../../core/state/app_state.dart';
import '../models/subscription.dart';

/// Interface for subscription data operations.
///
/// Implementations handle communication with the subscription backend
/// (Supabase + Stripe Billing).
abstract class ISubscriptionRepository {
  /// Get the current user's subscription.
  ///
  /// Returns null if user has no subscription record.
  Future<Subscription?> getMySubscription();

  /// Create a checkout session for upgrading to a new tier.
  ///
  /// Returns the data needed to present the Stripe payment sheet.
  Future<SubscriptionCheckoutResponse> createCheckout(AccountTier tier);

  /// Cancel the current subscription at period end.
  ///
  /// The subscription will remain active until the current period ends.
  Future<Subscription> cancelSubscription();

  /// Resume a subscription that was scheduled for cancellation.
  ///
  /// Only works if cancel_at_period_end was true and period hasn't ended.
  Future<Subscription> resumeSubscription();

  /// Get the URL for Stripe's customer portal.
  ///
  /// Allows users to manage payment methods, view invoices, etc.
  Future<CustomerPortalResponse> getCustomerPortalUrl();

  /// Verify a subscription status with Stripe and update the database.
  ///
  /// Called after payment to ensure the database reflects the actual
  /// Stripe subscription status.
  Future<void> verifySubscription(String subscriptionId);

  /// [Dev only] Override the subscription tier directly via edge function.
  ///
  /// Requires DEV_MODE=true on the server. Returns the updated subscription.
  Future<Subscription> devOverrideTier(AccountTier tier);
}
