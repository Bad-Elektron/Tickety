import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/payments/data/i_payment_repository.dart';
import '../../features/payments/data/payment_repository.dart';
import '../../features/payments/models/payment.dart';
import '../errors/errors.dart';
import '../services/services.dart';

const _tag = 'PaymentProvider';

/// State for ongoing payment processing.
class PaymentProcessState {
  final bool isLoading;
  final String? error;
  final PaymentIntentResponse? paymentIntent;
  final bool isPaymentSheetReady;
  final Payment? completedPayment;

  const PaymentProcessState({
    this.isLoading = false,
    this.error,
    this.paymentIntent,
    this.isPaymentSheetReady = false,
    this.completedPayment,
  });

  PaymentProcessState copyWith({
    bool? isLoading,
    String? error,
    PaymentIntentResponse? paymentIntent,
    bool? isPaymentSheetReady,
    Payment? completedPayment,
    bool clearError = false,
    bool clearPaymentIntent = false,
    bool clearCompletedPayment = false,
  }) {
    return PaymentProcessState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      paymentIntent: clearPaymentIntent ? null : (paymentIntent ?? this.paymentIntent),
      isPaymentSheetReady: isPaymentSheetReady ?? this.isPaymentSheetReady,
      completedPayment: clearCompletedPayment ? null : (completedPayment ?? this.completedPayment),
    );
  }

  bool get hasError => error != null;
  bool get isReady => paymentIntent != null && isPaymentSheetReady && !isLoading;
}

/// Notifier for processing a payment.
class PaymentProcessNotifier extends StateNotifier<PaymentProcessState> {
  final IPaymentRepository _repository;

  PaymentProcessNotifier(this._repository) : super(const PaymentProcessState());

  /// Initialize a payment for a primary ticket purchase.
  Future<bool> initializePrimaryPurchase({
    required String eventId,
    required int amountCents,
    String currency = 'usd',
    int quantity = 1,
    Map<String, dynamic>? metadata,
  }) async {
    if (state.isLoading) {
      AppLogger.debug('Already loading, skipping initialization', tag: _tag);
      return false;
    }

    AppLogger.info(
      'Initializing primary purchase: event=$eventId, amount=$amountCents cents, qty=$quantity',
      tag: _tag,
    );

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearPaymentIntent: true,
      isPaymentSheetReady: false,
    );

    try {
      // Create payment intent via Edge Function
      final request = CreatePaymentIntentRequest(
        eventId: eventId,
        amountCents: amountCents,
        currency: currency,
        type: PaymentType.primaryPurchase,
        quantity: quantity,
        metadata: metadata,
      );

      final paymentIntent = await _repository.createPaymentIntent(request);
      AppLogger.debug('Got payment intent: ${paymentIntent.paymentIntentId}', tag: _tag);

      // Initialize the Stripe Payment Sheet
      await StripeService.instance.initPaymentSheet(
        paymentIntentClientSecret: paymentIntent.clientSecret,
        customerId: paymentIntent.customerId,
        customerEphemeralKeySecret: paymentIntent.ephemeralKey,
      );

      AppLogger.info('Payment sheet ready for primary purchase', tag: _tag);

      state = state.copyWith(
        isLoading: false,
        paymentIntent: paymentIntent,
        isPaymentSheetReady: true,
      );

      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to initialize primary purchase',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
      return false;
    }
  }

  /// Initialize a payment for a resale purchase.
  Future<bool> initializeResalePurchase({
    required String resaleListingId,
    required int amountCents,
    String currency = 'usd',
  }) async {
    if (state.isLoading) return false;

    AppLogger.info(
      'Initializing resale purchase: listing=$resaleListingId, amount=$amountCents cents',
      tag: _tag,
    );

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearPaymentIntent: true,
      isPaymentSheetReady: false,
    );

    try {
      // Create payment intent via Edge Function
      final paymentIntent = await _repository.createResalePaymentIntent(
        resaleListingId: resaleListingId,
        amountCents: amountCents,
        currency: currency,
      );

      // Initialize the Stripe Payment Sheet
      await StripeService.instance.initPaymentSheet(
        paymentIntentClientSecret: paymentIntent.clientSecret,
        customerId: paymentIntent.customerId,
        customerEphemeralKeySecret: paymentIntent.ephemeralKey,
      );

      AppLogger.info('Payment sheet ready for resale purchase', tag: _tag);

      state = state.copyWith(
        isLoading: false,
        paymentIntent: paymentIntent,
        isPaymentSheetReady: true,
      );

      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to initialize resale purchase',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
      return false;
    }
  }

  /// Initialize a payment for vendor POS.
  Future<bool> initializeVendorPOS({
    required String eventId,
    required int amountCents,
    String currency = 'usd',
    Map<String, dynamic>? metadata,
  }) async {
    if (state.isLoading) return false;

    AppLogger.info(
      'Initializing vendor POS payment: event=$eventId, amount=$amountCents cents',
      tag: _tag,
    );

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearPaymentIntent: true,
      isPaymentSheetReady: false,
    );

    try {
      // Create payment intent via Edge Function
      final request = CreatePaymentIntentRequest(
        eventId: eventId,
        amountCents: amountCents,
        currency: currency,
        type: PaymentType.vendorPos,
        metadata: metadata,
      );

      final paymentIntent = await _repository.createPaymentIntent(request);

      // Initialize the Stripe Payment Sheet
      await StripeService.instance.initPaymentSheet(
        paymentIntentClientSecret: paymentIntent.clientSecret,
        customerId: paymentIntent.customerId,
        customerEphemeralKeySecret: paymentIntent.ephemeralKey,
      );

      AppLogger.info('Payment sheet ready for vendor POS', tag: _tag);

      state = state.copyWith(
        isLoading: false,
        paymentIntent: paymentIntent,
        isPaymentSheetReady: true,
      );

      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to initialize vendor POS payment',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
      return false;
    }
  }

  /// Present the payment sheet to the user.
  ///
  /// Returns true if payment was successful, false if cancelled.
  Future<bool> presentPaymentSheet() async {
    if (!state.isPaymentSheetReady) {
      AppLogger.warning('Payment sheet not ready', tag: _tag);
      return false;
    }

    AppLogger.info('Presenting payment sheet', tag: _tag);

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final success = await StripeService.instance.presentPaymentSheet();

      if (success) {
        AppLogger.info('Payment completed successfully', tag: _tag);

        // Fetch the completed payment record
        if (state.paymentIntent?.paymentId != null) {
          final payment = await _repository.getPayment(
            state.paymentIntent!.paymentId!,
          );
          state = state.copyWith(
            isLoading: false,
            completedPayment: payment,
          );
        } else {
          state = state.copyWith(isLoading: false);
        }

        return true;
      } else {
        AppLogger.info('Payment cancelled by user', tag: _tag);
        state = state.copyWith(isLoading: false);
        return false;
      }
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Payment failed',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
      return false;
    }
  }

  /// Clear the current payment state.
  void clear() {
    AppLogger.debug('Clearing payment state', tag: _tag);
    state = const PaymentProcessState();
  }

  /// Clear any error.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// State for user's payment history.
class PaymentHistoryState {
  final List<Payment> payments;
  final bool isLoading;
  final String? error;

  const PaymentHistoryState({
    this.payments = const [],
    this.isLoading = false,
    this.error,
  });

  PaymentHistoryState copyWith({
    List<Payment>? payments,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return PaymentHistoryState(
      payments: payments ?? this.payments,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Completed payments.
  List<Payment> get completedPayments {
    return payments.where((p) => p.status.isSuccessful).toList();
  }

  /// Pending payments.
  List<Payment> get pendingPayments {
    return payments.where((p) => p.status.isPending).toList();
  }

  /// Refunded payments.
  List<Payment> get refundedPayments {
    return payments.where((p) => p.status.isRefunded).toList();
  }

  /// Total spent in cents.
  int get totalSpentCents {
    return completedPayments.fold(0, (sum, p) => sum + p.amountCents);
  }
}

/// Notifier for user's payment history.
class PaymentHistoryNotifier extends StateNotifier<PaymentHistoryState> {
  final IPaymentRepository _repository;

  PaymentHistoryNotifier(this._repository) : super(const PaymentHistoryState());

  /// Load payment history.
  Future<void> load() async {
    if (state.isLoading) return;

    AppLogger.debug('Loading payment history', tag: _tag);

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final payments = await _repository.getMyPayments();
      AppLogger.info('Loaded ${payments.length} payments', tag: _tag);
      state = state.copyWith(
        payments: payments,
        isLoading: false,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load payment history',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
      );
    }
  }

  /// Refresh payment history.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: false);
    await load();
  }

  /// Request a refund for a payment.
  Future<bool> requestRefund(String paymentId) async {
    AppLogger.info('Requesting refund for: $paymentId', tag: _tag);

    try {
      final refundedPayment = await _repository.requestRefund(paymentId);

      // Update the payment in local state
      state = state.copyWith(
        payments: state.payments.map((p) {
          return p.id == paymentId ? refundedPayment : p;
        }).toList(),
      );

      AppLogger.info('Refund completed for: $paymentId', tag: _tag);
      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Refund failed for: $paymentId',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(error: appError.userMessage);
      return false;
    }
  }

  /// Clear error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ============================================================
// PROVIDERS
// ============================================================

/// Repository provider - can be overridden for testing.
final paymentRepositoryProvider = Provider<IPaymentRepository>((ref) {
  return PaymentRepository();
});

/// Payment processing provider for handling active payments.
final paymentProcessProvider =
    StateNotifierProvider<PaymentProcessNotifier, PaymentProcessState>((ref) {
  final repository = ref.watch(paymentRepositoryProvider);
  return PaymentProcessNotifier(repository);
});

/// Payment history provider for user's past payments.
final paymentHistoryProvider =
    StateNotifierProvider<PaymentHistoryNotifier, PaymentHistoryState>((ref) {
  final repository = ref.watch(paymentRepositoryProvider);
  return PaymentHistoryNotifier(repository);
});

/// Convenience provider for checking if a payment is in progress.
final paymentLoadingProvider = Provider<bool>((ref) {
  return ref.watch(paymentProcessProvider).isLoading;
});

/// Convenience provider for payment ready state.
final paymentReadyProvider = Provider<bool>((ref) {
  return ref.watch(paymentProcessProvider).isReady;
});

/// Convenience provider for payment error.
final paymentErrorProvider = Provider<String?>((ref) {
  return ref.watch(paymentProcessProvider).error;
});
