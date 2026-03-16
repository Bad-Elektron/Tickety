class WidgetConfig {
  final String id;
  final String organizerId;
  final String primaryColor;
  final String? accentColor;
  final String fontFamily;
  final String? logoUrl;
  final String buttonStyle;
  final bool showPoweredBy;
  final String? customCss;

  const WidgetConfig({
    required this.id,
    required this.organizerId,
    this.primaryColor = '#6366F1',
    this.accentColor,
    this.fontFamily = 'Inter',
    this.logoUrl,
    this.buttonStyle = 'rounded',
    this.showPoweredBy = true,
    this.customCss,
  });

  factory WidgetConfig.fromJson(Map<String, dynamic> json) {
    return WidgetConfig(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      primaryColor: json['primary_color'] as String? ?? '#6366F1',
      accentColor: json['accent_color'] as String?,
      fontFamily: json['font_family'] as String? ?? 'Inter',
      logoUrl: json['logo_url'] as String?,
      buttonStyle: json['button_style'] as String? ?? 'rounded',
      showPoweredBy: json['show_powered_by'] as bool? ?? true,
      customCss: json['custom_css'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'organizer_id': organizerId,
        'primary_color': primaryColor,
        'accent_color': accentColor,
        'font_family': fontFamily,
        'logo_url': logoUrl,
        'button_style': buttonStyle,
        'show_powered_by': showPoweredBy,
        'custom_css': customCss,
      };

  WidgetConfig copyWith({
    String? primaryColor,
    String? accentColor,
    String? fontFamily,
    String? logoUrl,
    String? buttonStyle,
    bool? showPoweredBy,
    String? customCss,
  }) {
    return WidgetConfig(
      id: id,
      organizerId: organizerId,
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      fontFamily: fontFamily ?? this.fontFamily,
      logoUrl: logoUrl ?? this.logoUrl,
      buttonStyle: buttonStyle ?? this.buttonStyle,
      showPoweredBy: showPoweredBy ?? this.showPoweredBy,
      customCss: customCss ?? this.customCss,
    );
  }
}
