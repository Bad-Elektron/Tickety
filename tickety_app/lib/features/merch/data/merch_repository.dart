import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../models/models.dart';

const _tag = 'MerchRepository';

/// Repository for merch store operations.
class MerchRepository {
  final _client = SupabaseService.instance.client;

  // ── Products ──────────────────────────────────────────────

  /// Get active products for an event (buyer-facing).
  Future<List<MerchProduct>> getEventProducts(String eventId) async {
    final response = await _client
        .from('merch_products')
        .select('*, merch_variants(*)')
        .eq('event_id', eventId)
        .eq('is_active', true)
        .order('created_at');

    return (response as List)
        .map((json) => MerchProduct.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get all products for an organizer (management).
  Future<List<MerchProduct>> getOrganizerProducts(String organizerId) async {
    final response = await _client
        .from('merch_products')
        .select('*, merch_variants(*)')
        .eq('organizer_id', organizerId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => MerchProduct.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get a single product with variants.
  Future<MerchProduct?> getProduct(String productId) async {
    final response = await _client
        .from('merch_products')
        .select('*, merch_variants(*)')
        .eq('id', productId)
        .maybeSingle();

    if (response == null) return null;
    return MerchProduct.fromJson(response);
  }

  /// Create a product (Stripe source).
  Future<MerchProduct> createProduct(MerchProduct product) async {
    final response = await _client
        .from('merch_products')
        .insert(product.toJson())
        .select('*, merch_variants(*)')
        .single();

    return MerchProduct.fromJson(response);
  }

  /// Update a product.
  Future<void> updateProduct(String productId, Map<String, dynamic> updates) async {
    await _client
        .from('merch_products')
        .update({...updates, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', productId);
  }

  /// Delete a product.
  Future<void> deleteProduct(String productId) async {
    await _client.from('merch_products').delete().eq('id', productId);
  }

  // ── Variants ──────────────────────────────────────────────

  /// Create a variant for a product.
  Future<MerchVariant> createVariant(MerchVariant variant) async {
    final response = await _client
        .from('merch_variants')
        .insert(variant.toJson())
        .select()
        .single();

    return MerchVariant.fromJson(response);
  }

  /// Update a variant.
  Future<void> updateVariant(String variantId, Map<String, dynamic> updates) async {
    await _client.from('merch_variants').update(updates).eq('id', variantId);
  }

  /// Delete a variant.
  Future<void> deleteVariant(String variantId) async {
    await _client.from('merch_variants').delete().eq('id', variantId);
  }

  // ── Config ──────────────────────────────────────────────

  /// Get organizer's merch config.
  Future<OrganizerMerchConfig?> getMerchConfig(String organizerId) async {
    final response = await _client
        .from('organizer_merch_config')
        .select()
        .eq('organizer_id', organizerId)
        .maybeSingle();

    if (response == null) return null;
    return OrganizerMerchConfig.fromJson(response);
  }

  /// Save (upsert) merch config.
  Future<OrganizerMerchConfig> saveMerchConfig(OrganizerMerchConfig config) async {
    final response = await _client
        .from('organizer_merch_config')
        .upsert(config.toJson(), onConflict: 'organizer_id')
        .select()
        .single();

    return OrganizerMerchConfig.fromJson(response);
  }

  // ── Shopify Sync ──────────────────────────────────────────

  /// Trigger Shopify product sync via edge function.
  Future<void> syncShopify(String organizerId) async {
    debugPrint('[$_tag] Syncing Shopify products for organizer: $organizerId');
    await _client.functions.invoke(
      'sync-shopify-products',
      body: {'organizer_id': organizerId},
    );
  }

  // ── Orders ──────────────────────────────────────────────

  /// Purchase a product via edge function.
  Future<Map<String, dynamic>> purchaseProduct({
    required String productId,
    String? variantId,
    required int quantity,
    required String fulfillmentType,
    Map<String, dynamic>? shippingAddress,
  }) async {
    final response = await _client.functions.invoke(
      'create-merch-payment',
      body: {
        'product_id': productId,
        if (variantId != null) 'variant_id': variantId,
        'quantity': quantity,
        'fulfillment_type': fulfillmentType,
        if (shippingAddress != null) 'shipping_address': shippingAddress,
      },
    );

    return response.data as Map<String, dynamic>;
  }

  /// Get buyer's orders.
  Future<List<MerchOrder>> getMyOrders() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('merch_orders')
        .select('*, merch_products(title, image_urls), merch_variants(name)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => MerchOrder.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get organizer's orders.
  Future<List<MerchOrder>> getOrganizerOrders(String organizerId) async {
    final response = await _client
        .from('merch_orders')
        .select('*, merch_products(title, image_urls), merch_variants(name)')
        .eq('organizer_id', organizerId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => MerchOrder.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Update order status (organizer action).
  Future<void> updateOrderStatus(String orderId, MerchOrderStatus status) async {
    await _client.from('merch_orders').update({
      'status': status.value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  /// Mark an order as shipped with tracking info.
  Future<void> markShipped(
    String orderId, {
    String? trackingUrl,
    String? carrier,
  }) async {
    await _client.from('merch_orders').update({
      'status': 'shipped',
      if (trackingUrl != null || carrier != null)
        'tracking_info': {
          if (trackingUrl != null) 'url': trackingUrl,
          if (carrier != null) 'carrier': carrier,
        },
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }
}
