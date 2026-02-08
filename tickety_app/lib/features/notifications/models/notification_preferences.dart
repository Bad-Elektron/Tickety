/// Model representing a user's notification preferences.
class NotificationPreferences {
  final String userId;
  final bool pushEnabled;
  final bool emailEnabled;
  final bool staffAdded;
  final bool ticketPurchased;
  final bool ticketUsed;
  final bool eventReminders;
  final bool eventUpdates;
  final bool marketing;
  final DateTime? updatedAt;

  const NotificationPreferences({
    required this.userId,
    this.pushEnabled = true,
    this.emailEnabled = true,
    this.staffAdded = true,
    this.ticketPurchased = true,
    this.ticketUsed = true,
    this.eventReminders = true,
    this.eventUpdates = true,
    this.marketing = false,
    this.updatedAt,
  });

  /// Default preferences for a new user.
  factory NotificationPreferences.defaults(String userId) {
    return NotificationPreferences(userId: userId);
  }

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      userId: json['user_id'] as String,
      pushEnabled: json['push_enabled'] as bool? ?? true,
      emailEnabled: json['email_enabled'] as bool? ?? true,
      staffAdded: json['staff_added'] as bool? ?? true,
      ticketPurchased: json['ticket_purchased'] as bool? ?? true,
      ticketUsed: json['ticket_used'] as bool? ?? true,
      eventReminders: json['event_reminders'] as bool? ?? true,
      eventUpdates: json['event_updates'] as bool? ?? true,
      marketing: json['marketing'] as bool? ?? false,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'push_enabled': pushEnabled,
      'email_enabled': emailEnabled,
      'staff_added': staffAdded,
      'ticket_purchased': ticketPurchased,
      'ticket_used': ticketUsed,
      'event_reminders': eventReminders,
      'event_updates': eventUpdates,
      'marketing': marketing,
    };
  }

  NotificationPreferences copyWith({
    String? userId,
    bool? pushEnabled,
    bool? emailEnabled,
    bool? staffAdded,
    bool? ticketPurchased,
    bool? ticketUsed,
    bool? eventReminders,
    bool? eventUpdates,
    bool? marketing,
    DateTime? updatedAt,
  }) {
    return NotificationPreferences(
      userId: userId ?? this.userId,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      staffAdded: staffAdded ?? this.staffAdded,
      ticketPurchased: ticketPurchased ?? this.ticketPurchased,
      ticketUsed: ticketUsed ?? this.ticketUsed,
      eventReminders: eventReminders ?? this.eventReminders,
      eventUpdates: eventUpdates ?? this.eventUpdates,
      marketing: marketing ?? this.marketing,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
