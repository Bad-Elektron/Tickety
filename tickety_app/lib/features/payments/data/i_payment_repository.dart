import '../../../core/models/models.dart';
import '../models/payment.dart';
import '../models/payment_method.dart';

/// Interface for payment data operations.
///
/// Implementations handle communication with the payment backend
/// (Supabase Edge Functions + Stripe).
abstract class IPaymentRepository {
  /// Create a payment intent for a ticket purchase.
  ///
  /// Returns the client secret and other data needed to complete the payment.
  Future<PaymentIntentResponse> createPaymentIntent(
    CreatePaymentIntentRequest request,
  );

  /// Create a payment intent for a resale purchase.
  ///
  /// This includes platform fee calculation and transfer to seller.
  Future<PaymentIntentResponse> createResalePaymentIntent({
    required String resaleListingId,
    required int amountCents,
    String currency = 'usd',
  });

  /// Get a payment by ID.
  Future<Payment?> getPayment(String paymentId);

  /// Get payments for the current user.
  ///
  /// Returns a paginated result with payments ordered by creation date (newest first).
  /// [page] is 0-indexed.
  Future<PaginatedResult<Payment>> getMyPayments({
    int page = 0,
    int pageSize = 25,
  });

  /// Get payments for a specific event (organizer view).
  ///
  /// Returns a paginated result with payments ordered by creation date (newest first).
  /// [page] is 0-indexed.
  Future<PaginatedResult<Payment>> getEventPayments(
    String eventId, {
    int page = 0,
    int pageSize = 20,
  });

  /// Request a refund for a payment.
  ///
  /// Returns the updated payment with refunded status.
  Future<Payment> requestRefund(String paymentId);

  /// Update payment status (typically called by webhooks).
  Future<Payment> updatePaymentStatus(
    String paymentId,
    PaymentStatus status, {
    String? stripeChargeId,
    String? ticketId,
  });

  /// Get saved payment methods (cards) for the current user.
  Future<List<PaymentMethodCard>> getPaymentMethods();

  /// Create a setup intent for adding a new card.
  Future<SetupIntentResponse> createSetupIntent();

  /// Delete (detach) a saved payment method.
  Future<void> deletePaymentMethod(String paymentMethodId);

  /// Set a payment method as the default for the customer.
  Future<void> setDefaultPaymentMethod(String paymentMethodId);
}
