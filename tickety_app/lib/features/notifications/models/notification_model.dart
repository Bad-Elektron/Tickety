/// Types of notifications in the app.
enum NotificationType {
  staffAdded('staff_added'),
  ticketPurchased('ticket_purchased'),
  ticketUsed('ticket_used'),
  eventReminder('event_reminder'),
  unknown('unknown');

  const NotificationType(this.value);

  final String value;

  static NotificationType fromString(String? value) {
    if (value == null) return NotificationType.unknown;
    return NotificationType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => NotificationType.unknown,
    );
  }
}

/// Model representing an in-app notification.
class NotificationModel {
  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.read,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: NotificationType.fromString(json['type'] as String?),
      title: json['title'] as String,
      body: json['body'] as String,
      data: (json['data'] as Map<String, dynamic>?) ?? {},
      read: json['read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.value,
      'title': title,
      'body': body,
      'data': data,
      'read': read,
      'created_at': createdAt.toIso8601String(),
    };
  }

  NotificationModel copyWith({
    String? id,
    String? userId,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    bool? read,
    DateTime? createdAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      read: read ?? this.read,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Get event ID from notification data (for staff_added type).
  String? get eventId => data['event_id'] as String?;

  /// Get event title from notification data.
  String? get eventTitle => data['event_title'] as String?;

  /// Get role from notification data (for staff_added type).
  String? get role => data['role'] as String?;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotificationModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
