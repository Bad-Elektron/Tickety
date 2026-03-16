import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../../core/services/services.dart';
import '../models/widget_api_key.dart';
import '../models/widget_config.dart';

class WidgetRepository {
  final _client = SupabaseService.instance.client;

  // ── API Keys ──────────────────────────────────────────

  Future<List<WidgetApiKey>> getApiKeys() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('widget_api_keys')
        .select()
        .eq('organizer_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => WidgetApiKey.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Creates a new API key. Returns the key with [rawKey] populated (only time it's available).
  Future<WidgetApiKey> createApiKey({
    String? label,
    List<String>? allowedEventIds,
    List<String>? allowedOrigins,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // Generate a secure random key
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final rawKey = 'twk_live_${base64Url.encode(bytes).replaceAll('=', '')}';

    // Hash for storage
    final keyHash = sha256.convert(utf8.encode(rawKey)).toString();

    final response = await _client
        .from('widget_api_keys')
        .insert({
          'organizer_id': userId,
          'key_prefix': 'twk_live_',
          'key_hash': keyHash,
          'label': label,
          'allowed_event_ids': allowedEventIds,
          'allowed_origins': allowedOrigins,
        })
        .select()
        .single();

    final key = WidgetApiKey.fromJson(response);
    return WidgetApiKey(
      id: key.id,
      organizerId: key.organizerId,
      keyPrefix: key.keyPrefix,
      label: key.label,
      allowedEventIds: key.allowedEventIds,
      allowedOrigins: key.allowedOrigins,
      isActive: key.isActive,
      rateLimitPerMinute: key.rateLimitPerMinute,
      createdAt: key.createdAt,
      lastUsedAt: key.lastUsedAt,
      rawKey: rawKey,
    );
  }

  Future<void> updateApiKey(
    String keyId, {
    String? label,
    List<String>? allowedOrigins,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{};
    if (label != null) updates['label'] = label;
    if (allowedOrigins != null) updates['allowed_origins'] = allowedOrigins;
    if (isActive != null) updates['is_active'] = isActive;

    if (updates.isEmpty) return;

    await _client.from('widget_api_keys').update(updates).eq('id', keyId);
  }

  Future<void> deleteApiKey(String keyId) async {
    await _client.from('widget_api_keys').delete().eq('id', keyId);
  }

  // ── Widget Config ─────────────────────────────────────

  Future<WidgetConfig?> getConfig() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return null;

    final response = await _client
        .from('widget_configs')
        .select()
        .eq('organizer_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return WidgetConfig.fromJson(response);
  }

  Future<WidgetConfig> upsertConfig(WidgetConfig config) async {
    final response = await _client
        .from('widget_configs')
        .upsert(config.toJson())
        .select()
        .single();

    return WidgetConfig.fromJson(response);
  }
}
