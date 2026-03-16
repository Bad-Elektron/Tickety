class WidgetApiKey {
  final String id;
  final String organizerId;
  final String keyPrefix;
  final String? label;
  final List<String>? allowedEventIds;
  final List<String>? allowedOrigins;
  final bool isActive;
  final int rateLimitPerMinute;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  /// Only available when the key is first created (not stored in DB).
  final String? rawKey;

  const WidgetApiKey({
    required this.id,
    required this.organizerId,
    this.keyPrefix = 'twk_live_',
    this.label,
    this.allowedEventIds,
    this.allowedOrigins,
    this.isActive = true,
    this.rateLimitPerMinute = 100,
    required this.createdAt,
    this.lastUsedAt,
    this.rawKey,
  });

  factory WidgetApiKey.fromJson(Map<String, dynamic> json) {
    return WidgetApiKey(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      keyPrefix: json['key_prefix'] as String? ?? 'twk_live_',
      label: json['label'] as String?,
      allowedEventIds: (json['allowed_event_ids'] as List?)?.cast<String>(),
      allowedOrigins: (json['allowed_origins'] as List?)?.cast<String>(),
      isActive: json['is_active'] as bool? ?? true,
      rateLimitPerMinute: json['rate_limit_per_minute'] as int? ?? 100,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'] as String)
          : null,
    );
  }
}
