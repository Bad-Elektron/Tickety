import 'dart:ui';

/// Organizer branding configuration (custom colors + logo).
class OrganizerBranding {
  final String organizerId;
  final String primaryColor;
  final String? accentColor;
  final String? logoUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OrganizerBranding({
    required this.organizerId,
    this.primaryColor = '#6366F1',
    this.accentColor,
    this.logoUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrganizerBranding.fromJson(Map<String, dynamic> json) {
    return OrganizerBranding(
      organizerId: json['organizer_id'] as String,
      primaryColor: json['primary_color'] as String? ?? '#6366F1',
      accentColor: json['accent_color'] as String?,
      logoUrl: json['logo_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'organizer_id': organizerId,
        'primary_color': primaryColor,
        'accent_color': accentColor,
        'logo_url': logoUrl,
      };

  OrganizerBranding copyWith({
    String? primaryColor,
    String? accentColor,
    String? logoUrl,
  }) {
    return OrganizerBranding(
      organizerId: organizerId,
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      logoUrl: logoUrl ?? this.logoUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Parse hex color string to Flutter Color.
  Color get primaryColorValue => _parseHex(primaryColor);

  /// Parse accent hex color, falls back to primary with reduced opacity.
  Color get accentColorValue =>
      accentColor != null ? _parseHex(accentColor!) : primaryColorValue;

  bool get hasLogo => logoUrl != null && logoUrl!.isNotEmpty;

  static Color _parseHex(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return const Color(0xFF6366F1);
    return Color(0xFF000000 | value);
  }
}
