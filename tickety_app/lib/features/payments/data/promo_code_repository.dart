import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/promo_code.dart';

const _tag = 'PromoCodeRepository';

/// Repository for promo code operations.
class PromoCodeRepository {
  final _client = SupabaseService.instance.client;

  /// Validate a promo code via edge function.
  Future<PromoValidationResult> validateCode({
    required String eventId,
    required String code,
    required int basePriceCents,
    String? ticketTypeId,
  }) async {
    AppLogger.info(
      'Validating promo code: event=$eventId, code=$code',
      tag: _tag,
    );

    await _client.auth.refreshSession();

    final response = await _client.functions.invoke(
      'validate-promo-code',
      body: {
        'event_id': eventId,
        'code': code,
        'base_price_cents': basePriceCents,
        if (ticketTypeId != null) 'ticket_type_id': ticketTypeId,
      },
    );

    if (response.status != 200) {
      final error = response.data is Map
          ? response.data['error'] as String?
          : 'Unknown error';
      throw PaymentException(
        error ?? 'Failed to validate promo code',
        technicalDetails: 'Edge function error (${response.status}): $error',
      );
    }

    final data = response.data as Map<String, dynamic>;
    AppLogger.info('Promo validation result: $data', tag: _tag);
    return PromoValidationResult.fromJson(data);
  }

  /// Get all promo codes for an event (organizer).
  Future<List<PromoCode>> getEventPromoCodes(String eventId) async {
    AppLogger.info('Loading promo codes for event=$eventId', tag: _tag);

    final response = await _client
        .from('promo_codes')
        .select()
        .eq('event_id', eventId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => PromoCode.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Create a new promo code.
  Future<PromoCode> createPromoCode({
    required String eventId,
    required String code,
    required PromoDiscountType discountType,
    required int discountValue,
    int? maxUses,
    DateTime? validFrom,
    DateTime? validUntil,
    String? ticketTypeId,
  }) async {
    AppLogger.info(
      'Creating promo code: event=$eventId, code=$code, type=${discountType.value}, value=$discountValue',
      tag: _tag,
    );

    final response = await _client
        .from('promo_codes')
        .insert({
          'event_id': eventId,
          'code': code.toUpperCase(),
          'discount_type': discountType.value,
          'discount_value': discountValue,
          if (maxUses != null) 'max_uses': maxUses,
          if (validFrom != null) 'valid_from': validFrom.toIso8601String(),
          if (validUntil != null) 'valid_until': validUntil.toIso8601String(),
          if (ticketTypeId != null) 'ticket_type_id': ticketTypeId,
        })
        .select()
        .single();

    AppLogger.info('Promo code created: ${response['id']}', tag: _tag);
    return PromoCode.fromJson(response);
  }

  /// Deactivate a promo code.
  Future<void> deactivatePromoCode(String id) async {
    AppLogger.info('Deactivating promo code: $id', tag: _tag);

    await _client
        .from('promo_codes')
        .update({'is_active': false})
        .eq('id', id);
  }

  /// Reactivate a promo code.
  Future<void> activatePromoCode(String id) async {
    AppLogger.info('Activating promo code: $id', tag: _tag);

    await _client
        .from('promo_codes')
        .update({'is_active': true})
        .eq('id', id);
  }
}
