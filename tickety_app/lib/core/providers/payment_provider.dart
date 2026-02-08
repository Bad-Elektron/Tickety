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
      print('>>> CHECKOUT: paymentIntentId=${paymentIntent.paymentIntentId}, '
          'customerId=${paymentIntent.customerId}, '
          'hasEphemeralKey=${paymentIntent.ephemeralKey != null}, '
          'ephemeralKeyLength=${paymentIntent.ephemeralKey?.length ?? 0}');

      // Initialize the Stripe Payment Sheet
      await StripeService.instance.initPaymentSheet(
        paymentIntentClientSecret: paymentIntent.clientSecret,
        customerId: paymentIntent.customerId,
        customerEphemeralKeySecret: paymentIntent.ephemeralKey,
      );

      print('>>> CHECKOUT: Payment sheet initialized successfully');

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
      print('>>> PROVIDER: Step 1 - Calling createResalePaymentIntent...');
      final paymentIntent = await _repository.createResalePaymentIntent(
        resaleListingId: resaleListingId,
        amountCents: amountCents,
        currency: currency,
      );
      print('>>> PROVIDER: Step 1 SUCCESS - Got paymentIntent id=${paymentIntent.paymentIntentId}');

      // Initialize the Stripe Payment Sheet
      print('>>> PROVIDER: Step 2 - Initializing Stripe Payment Sheet...');
      await StripeService.instance.initPaymentSheet(
        paymentIntentClientSecret: paymentIntent.clientSecret,
        customerId: paymentIntent.customerId,
        customerEphemeralKeySecret: paymentIntent.ephemeralKey,
      );
      print('>>> PROVIDER: Step 2 SUCCESS - Payment sheet initialized');

      AppLogger.info('Payment sheet ready for resale purchase', tag: _tag);

      state = state.copyWith(
        isLoading: false,
        paymentIntent: paymentIntent,
        isPaymentSheetReady: true,
      );

      return true;
    } catch (e, s) {
      print('>>> PROVIDER ERROR: ${e.runtimeType}: $e');
      print('>>> PROVIDER ERROR STACK: $s');
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to initialize resale purchase: ${e.runtimeType}: $e',
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

/// Default page size for payment history pagination.
const int kPaymentHistoryPageSize = 25;

/// State for user's payment history.
class PaymentHistoryState {
  final List<Payment> payments;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int currentPage;
  final bool hasMore;
  final int pageSize;

  const PaymentHistoryState({
    this.payments = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.currentPage = 0,
    this.hasMore = true,
    this.pageSize = kPaymentHistoryPageSize,
  });

  /// Whether more payments can be loaded.
  bool get canLoadMore => hasMore && !isLoading && !isLoadingMore;

  PaymentHistoryState copyWith({
    List<Payment>? payments,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    int? currentPage,
    bool? hasMore,
    int? pageSize,
    bool clearError = false,
  }) {
    return PaymentHistoryState(
      payments: payments ?? this.payments,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      pageSize: pageSize ?? this.pageSize,
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

  /// Total spent in cents (from loaded payments).
  int get totalSpentCents {
    return completedPayments.fold(0, (sum, p) => sum + p.amountCents);
  }
}

/// Notifier for user's payment history.
class PaymentHistoryNotifier extends StateNotifier<PaymentHistoryState> {
  final IPaymentRepository _repository;

  PaymentHistoryNotifier(this._repository) : super(const PaymentHistoryState());

  /// Load the first page of payment history.
  Future<void> load() async {
    if (state.isLoading) return;

    AppLogger.debug('Loading payment history', tag: _tag);

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentPage: 0,
      hasMore: true,
    );

    try {
      final result = await _repository.getMyPayments(
        page: 0,
        pageSize: state.pageSize,
      );
      AppLogger.info(
        'Loaded ${result.items.length} payments (hasMore: ${result.hasMore})',
        tag: _tag,
      );
      state = state.copyWith(
        payments: result.items,
        isLoading: false,
        currentPage: 0,
        hasMore: result.hasMore,
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
        hasMore: false,
      );
    }
  }

  /// Load more payments (next page).
  Future<void> loadMore() async {
    if (!state.canLoadMore) {
      AppLogger.debug(
        'Cannot load more payments: canLoadMore=${state.canLoadMore}',
        tag: _tag,
      );
      return;
    }

    final nextPage = state.currentPage + 1;
    AppLogger.debug('Loading more payments (page: $nextPage)', tag: _tag);
    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _repository.getMyPayments(
        page: nextPage,
        pageSize: state.pageSize,
      );

      AppLogger.info(
        'Loaded ${result.items.length} more payments (hasMore: ${result.hasMore})',
        tag: _tag,
      );

      state = state.copyWith(
        payments: [...state.payments, ...result.items],
        isLoadingMore: false,
        currentPage: nextPage,
        hasMore: result.hasMore,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load more payments',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoadingMore: false,
        error: appError.userMessage,
      );
    }
  }

  /// Refresh payment history (reload first page).
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

/// Convenience provider for payment history loading more state.
final paymentHistoryLoadingMoreProvider = Provider<bool>((ref) {
  return ref.watch(paymentHistoryProvider).isLoadingMore;
});

/// Convenience provider for payment history can load more state.
final paymentHistoryCanLoadMoreProvider = Provider<bool>((ref) {
  return ref.watch(paymentHistoryProvider).canLoadMore;
});
