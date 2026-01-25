import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/payment.dart';
import 'i_payment_repository.dart';

const _tag = 'PaymentRepository';

/// Supabase implementation of [IPaymentRepository].
///
/// Uses Edge Functions for payment intent creation (security)
/// and direct database access for reading payment records.
class PaymentRepository implements IPaymentRepository {
  final _client = SupabaseService.instance.client;

  @override
  Future<PaymentIntentResponse> createPaymentIntent(
    CreatePaymentIntentRequest request,
  ) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info(
      'Creating payment intent: event=${request.eventId}, amount=${request.amountCents} cents, qty=${request.quantity}',
      tag: _tag,
    );

    final response = await _client.functions.invoke(
      'create-payment-intent',
      body: {
        ...request.toJson(),
        'user_id': userId,
      },
    );

    if (response.status != 200) {
      final error = response.data is Map ? response.data['error'] : 'Unknown error';
      AppLogger.error(
        'Failed to create payment intent: status=${response.status}, error=$error',
        tag: _tag,
      );
      throw PaymentException(
        'Failed to initiate payment: $error',
        technicalDetails: 'Edge function error (${response.status}): $error',
      );
    }

    final data = response.data as Map<String, dynamic>;
    AppLogger.info('Payment intent created: ${data['payment_intent_id']}', tag: _tag);
    return PaymentIntentResponse.fromJson(data);
  }

  @override
  Future<PaymentIntentResponse> createResalePaymentIntent({
    required String resaleListingId,
    required int amountCents,
    String currency = 'usd',
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw AuthException.notAuthenticated();
    }

    AppLogger.info(
      'Creating resale payment intent: listing=$resaleListingId, amount=$amountCents cents',
      tag: _tag,
    );

    final response = await _client.functions.invoke(
      'create-resale-intent',
      body: {
        'resale_listing_id': resaleListingId,
        'amount_cents': amountCents,
        'currency': currency,
        'user_id': userId,
      },
    );

    if (response.status != 200) {
      final error = response.data is Map ? response.data['error'] : 'Unknown error';
      AppLogger.error(
        'Failed to create resale payment intent: $error',
        tag: _tag,
      );

      // Check for specific error types
      if (error.toString().contains('Connect account')) {
        throw PaymentException.connectAccountRequired();
      }

      throw PaymentException(
        'Failed to initiate payment. Please try again.',
        technicalDetails: 'Edge function error: $error',
      );
    }

    final data = response.data as Map<String, dynamic>;
    AppLogger.info('Resale payment intent created: ${data['payment_intent_id']}', tag: _tag);
    return PaymentIntentResponse.fromJson(data);
  }

  @override
  Future<Payment?> getPayment(String paymentId) async {
    AppLogger.debug('Fetching payment: $paymentId', tag: _tag);

    final response = await _client
        .from('payments')
        .select()
        .eq('id', paymentId)
        .maybeSingle();

    if (response == null) {
      AppLogger.debug('Payment not found: $paymentId', tag: _tag);
      return null;
    }

    return Payment.fromJson(response);
  }

  @override
  Future<List<Payment>> getMyPayments() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.debug('No current user for payments', tag: _tag);
      return [];
    }

    AppLogger.debug('Fetching payments for user: $userId', tag: _tag);

    final response = await _client
        .from('payments')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final payments = (response as List<dynamic>)
        .map((json) => Payment.fromJson(json as Map<String, dynamic>))
        .toList();

    AppLogger.debug('Found ${payments.length} payments', tag: _tag);
    return payments;
  }

  @override
  Future<List<Payment>> getEventPayments(String eventId) async {
    AppLogger.debug('Fetching payments for event: $eventId', tag: _tag);

    final response = await _client
        .from('payments')
        .select()
        .eq('event_id', eventId)
        .order('created_at', ascending: false);

    final payments = (response as List<dynamic>)
        .map((json) => Payment.fromJson(json as Map<String, dynamic>))
        .toList();

    AppLogger.debug('Found ${payments.length} event payments', tag: _tag);
    return payments;
  }

  @override
  Future<Payment> requestRefund(String paymentId) async {
    AppLogger.info('Requesting refund for payment: $paymentId', tag: _tag);

    final response = await _client.functions.invoke(
      'process-refund',
      body: {
        'payment_id': paymentId,
      },
    );

    if (response.status != 200) {
      final error = response.data is Map ? response.data['error'] : 'Unknown error';
      AppLogger.error(
        'Failed to process refund: $error',
        tag: _tag,
      );

      if (error.toString().contains('already refunded')) {
        throw PaymentException.alreadyRefunded();
      }

      throw PaymentException.refundFailed(error.toString());
    }

    final data = response.data as Map<String, dynamic>;
    AppLogger.info('Refund processed for payment: $paymentId', tag: _tag);
    return Payment.fromJson(data['payment'] as Map<String, dynamic>);
  }

  @override
  Future<Payment> updatePaymentStatus(
    String paymentId,
    PaymentStatus status, {
    String? stripeChargeId,
    String? ticketId,
  }) async {
    AppLogger.debug(
      'Updating payment status: $paymentId -> ${status.value}',
      tag: _tag,
    );

    final updates = <String, dynamic>{
      'status': status.value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (stripeChargeId != null) {
      updates['stripe_charge_id'] = stripeChargeId;
    }

    if (ticketId != null) {
      updates['ticket_id'] = ticketId;
    }

    final response = await _client
        .from('payments')
        .update(updates)
        .eq('id', paymentId)
        .select()
        .single();

    final payment = Payment.fromJson(response);
    AppLogger.info(
      'Payment status updated: $paymentId -> ${status.value}',
      tag: _tag,
    );
    return payment;
  }
}
