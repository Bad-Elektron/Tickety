import '../models/payment.dart';

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

  /// Get all payments for the current user.
  Future<List<Payment>> getMyPayments();

  /// Get payments for a specific event (organizer view).
  Future<List<Payment>> getEventPayments(String eventId);

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
}
