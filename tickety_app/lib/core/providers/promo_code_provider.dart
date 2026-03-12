import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/payments/data/promo_code_repository.dart';
import '../../features/payments/models/promo_code.dart';
import '../errors/errors.dart';

const _tag = 'PromoCodeProvider';

// ============================================================
// Repository
// ============================================================

final promoCodeRepositoryProvider = Provider<PromoCodeRepository>((ref) {
  return PromoCodeRepository();
});

// ============================================================
// Buyer: Promo Validation (checkout)
// ============================================================

/// State for promo code validation during checkout.
class PromoValidationState {
  final bool isValidating;
  final PromoValidationResult? result;
  final String? appliedCode;
  final String? error;

  const PromoValidationState({
    this.isValidating = false,
    this.result,
    this.appliedCode,
    this.error,
  });

  PromoValidationState copyWith({
    bool? isValidating,
    PromoValidationResult? result,
    String? appliedCode,
    String? error,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return PromoValidationState(
      isValidating: isValidating ?? this.isValidating,
      result: clearResult ? null : (result ?? this.result),
      appliedCode: clearResult ? null : (appliedCode ?? this.appliedCode),
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get hasDiscount => result != null && result!.valid;
  int get discountCents => result?.discountCents ?? 0;
  String? get promoCodeId => result?.promoCodeId;
}

class PromoValidationNotifier extends StateNotifier<PromoValidationState> {
  final PromoCodeRepository _repository;

  PromoValidationNotifier(this._repository)
      : super(const PromoValidationState());

  /// Validate a promo code.
  Future<void> validateCode({
    required String eventId,
    required String code,
    required int basePriceCents,
    String? ticketTypeId,
  }) async {
    if (state.isValidating) return;

    AppLogger.info('Validating promo code: $code', tag: _tag);
    state = state.copyWith(
      isValidating: true,
      clearError: true,
      clearResult: true,
    );

    try {
      final result = await _repository.validateCode(
        eventId: eventId,
        code: code,
        basePriceCents: basePriceCents,
        ticketTypeId: ticketTypeId,
      );

      if (result.valid) {
        AppLogger.info(
          'Promo code valid: discount=${result.discountCents} cents',
          tag: _tag,
        );
        state = state.copyWith(
          isValidating: false,
          result: result,
          appliedCode: code.toUpperCase(),
        );
      } else {
        state = state.copyWith(
          isValidating: false,
          error: result.error ?? 'Invalid code',
        );
      }
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to validate promo code',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isValidating: false,
        error: appError.userMessage,
      );
    }
  }

  /// Clear the applied promo code.
  void clearCode() {
    state = const PromoValidationState();
  }
}

/// Provider for promo code validation during checkout.
final promoValidationProvider =
    StateNotifierProvider<PromoValidationNotifier, PromoValidationState>((ref) {
  final repository = ref.watch(promoCodeRepositoryProvider);
  return PromoValidationNotifier(repository);
});

// ============================================================
// Organizer: Promo Code Management
// ============================================================

/// State for organizer promo code management.
class PromoCodeManagementState {
  final List<PromoCode> codes;
  final bool isLoading;
  final String? error;

  const PromoCodeManagementState({
    this.codes = const [],
    this.isLoading = false,
    this.error,
  });

  PromoCodeManagementState copyWith({
    List<PromoCode>? codes,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return PromoCodeManagementState(
      codes: codes ?? this.codes,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PromoCodeManagementNotifier
    extends StateNotifier<PromoCodeManagementState> {
  final PromoCodeRepository _repository;

  PromoCodeManagementNotifier(this._repository)
      : super(const PromoCodeManagementState());

  /// Load promo codes for an event.
  Future<void> loadCodes(String eventId) async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final codes = await _repository.getEventPromoCodes(eventId);
      AppLogger.info('Loaded ${codes.length} promo codes', tag: _tag);
      state = state.copyWith(codes: codes, isLoading: false);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load promo codes',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
    }
  }

  /// Create a new promo code.
  Future<bool> createCode({
    required String eventId,
    required String code,
    required PromoDiscountType discountType,
    required int discountValue,
    int? maxUses,
    DateTime? validFrom,
    DateTime? validUntil,
    String? ticketTypeId,
  }) async {
    try {
      final newCode = await _repository.createPromoCode(
        eventId: eventId,
        code: code,
        discountType: discountType,
        discountValue: discountValue,
        maxUses: maxUses,
        validFrom: validFrom,
        validUntil: validUntil,
        ticketTypeId: ticketTypeId,
      );
      state = state.copyWith(codes: [newCode, ...state.codes]);
      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to create promo code',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(error: appError.userMessage);
      return false;
    }
  }

  /// Deactivate a promo code.
  Future<void> deactivateCode(String id) async {
    try {
      await _repository.deactivatePromoCode(id);
      state = state.copyWith(
        codes: state.codes.map((c) {
          if (c.id == id) {
            return PromoCode(
              id: c.id,
              eventId: c.eventId,
              code: c.code,
              discountType: c.discountType,
              discountValue: c.discountValue,
              maxUses: c.maxUses,
              currentUses: c.currentUses,
              validFrom: c.validFrom,
              validUntil: c.validUntil,
              ticketTypeId: c.ticketTypeId,
              isActive: false,
              createdAt: c.createdAt,
            );
          }
          return c;
        }).toList(),
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to deactivate promo code',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(error: appError.userMessage);
    }
  }

  /// Activate a promo code.
  Future<void> activateCode(String id) async {
    try {
      await _repository.activatePromoCode(id);
      state = state.copyWith(
        codes: state.codes.map((c) {
          if (c.id == id) {
            return PromoCode(
              id: c.id,
              eventId: c.eventId,
              code: c.code,
              discountType: c.discountType,
              discountValue: c.discountValue,
              maxUses: c.maxUses,
              currentUses: c.currentUses,
              validFrom: c.validFrom,
              validUntil: c.validUntil,
              ticketTypeId: c.ticketTypeId,
              isActive: true,
              createdAt: c.createdAt,
            );
          }
          return c;
        }).toList(),
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to activate promo code',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(error: appError.userMessage);
    }
  }
}

/// Provider for managing promo codes (organizer), keyed by event ID.
final promoCodeManagementProvider = StateNotifierProvider.family<
    PromoCodeManagementNotifier, PromoCodeManagementState, String>((ref, eventId) {
  final repository = ref.watch(promoCodeRepositoryProvider);
  return PromoCodeManagementNotifier(repository);
});
