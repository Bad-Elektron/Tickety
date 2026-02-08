import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/payments/data/i_payment_repository.dart';
import '../../features/payments/models/payment_method.dart';
import '../errors/errors.dart';
import '../services/services.dart';
import 'payment_provider.dart';

const _tag = 'PaymentMethodsProvider';

/// State for the user's saved payment methods.
class PaymentMethodsState {
  final List<PaymentMethodCard> methods;
  final bool isLoading;
  final String? error;

  const PaymentMethodsState({
    this.methods = const [],
    this.isLoading = false,
    this.error,
  });

  PaymentMethodsState copyWith({
    List<PaymentMethodCard>? methods,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return PaymentMethodsState(
      methods: methods ?? this.methods,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get hasError => error != null;
  bool get isEmpty => methods.isEmpty && !isLoading;

  PaymentMethodCard? get defaultMethod {
    try {
      return methods.firstWhere((m) => m.isDefault);
    } catch (_) {
      return methods.isNotEmpty ? methods.first : null;
    }
  }
}

/// Notifier for managing saved payment methods.
class PaymentMethodsNotifier extends StateNotifier<PaymentMethodsState> {
  final IPaymentRepository _repository;

  PaymentMethodsNotifier(this._repository) : super(const PaymentMethodsState());

  /// Load all saved payment methods.
  Future<void> load() async {
    if (state.isLoading) return;

    AppLogger.debug('Loading payment methods', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final methods = await _repository.getPaymentMethods();
      AppLogger.info('Loaded ${methods.length} payment methods', tag: _tag);
      state = state.copyWith(methods: methods, isLoading: false);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load payment methods',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
    }
  }

  /// Add a new card via Stripe setup sheet.
  ///
  /// Returns true if a card was added successfully.
  Future<bool> addCard() async {
    if (!StripeService.isSupported) {
      state = state.copyWith(error: 'Card management is only available on mobile devices');
      return false;
    }

    AppLogger.info('Starting add card flow', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Create setup intent
      final setupIntent = await _repository.createSetupIntent();
      AppLogger.debug('Got setup intent: ${setupIntent.setupIntentId}', tag: _tag);

      // Initialize payment sheet in setup mode
      await StripeService.instance.initSetupSheet(
        setupIntentClientSecret: setupIntent.clientSecret,
        customerId: setupIntent.customerId,
        customerEphemeralKeySecret: setupIntent.ephemeralKey,
      );

      // Present the sheet
      final success = await StripeService.instance.presentPaymentSheet();

      if (success) {
        AppLogger.info('Card added successfully', tag: _tag);
        // Reload to get the new card
        state = state.copyWith(isLoading: false);
        await load();
        return true;
      } else {
        AppLogger.info('Add card cancelled by user', tag: _tag);
        state = state.copyWith(isLoading: false);
        return false;
      }
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to add card',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
      return false;
    }
  }

  /// Delete a saved card.
  Future<bool> deleteCard(String paymentMethodId) async {
    AppLogger.info('Deleting card: $paymentMethodId', tag: _tag);

    try {
      await _repository.deletePaymentMethod(paymentMethodId);

      // Remove from local state immediately
      state = state.copyWith(
        methods: state.methods.where((m) => m.id != paymentMethodId).toList(),
      );

      AppLogger.info('Card deleted: $paymentMethodId', tag: _tag);
      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to delete card',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(error: appError.userMessage);
      return false;
    }
  }

  /// Set a card as the default payment method.
  Future<bool> setDefault(String paymentMethodId) async {
    AppLogger.info('Setting default card: $paymentMethodId', tag: _tag);

    try {
      await _repository.setDefaultPaymentMethod(paymentMethodId);

      // Update local state immediately
      state = state.copyWith(
        methods: state.methods.map((m) {
          return PaymentMethodCard(
            id: m.id,
            brand: m.brand,
            last4: m.last4,
            expMonth: m.expMonth,
            expYear: m.expYear,
            isDefault: m.id == paymentMethodId,
          );
        }).toList(),
      );

      AppLogger.info('Default card updated: $paymentMethodId', tag: _tag);
      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to set default card',
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

/// Payment methods provider for managing saved cards.
final paymentMethodsProvider =
    StateNotifierProvider<PaymentMethodsNotifier, PaymentMethodsState>((ref) {
  final repository = ref.watch(paymentRepositoryProvider);
  return PaymentMethodsNotifier(repository);
});
