/// Staff roles for event management.
enum StaffRole {
  usher('usher', 'Usher', 'Can check tickets at entry'),
  seller('seller', 'Seller', 'Can sell tickets on the spot'),
  manager('manager', 'Manager', 'Full access to event management');

  const StaffRole(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;

  static StaffRole? fromString(String? value) {
    if (value == null) return null;
    return StaffRole.values.where((r) => r.value == value).firstOrNull;
  }
}

/// Represents a staff assignment to an event.
class EventStaff {
  final String id;
  final String eventId;
  final String userId;
  final StaffRole role;
  final String? invitedEmail;
  final DateTime? acceptedAt;
  final DateTime createdAt;

  // Joined data
  final String? userName;
  final String? userEmail;

  const EventStaff({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.role,
    this.invitedEmail,
    this.acceptedAt,
    required this.createdAt,
    this.userName,
    this.userEmail,
  });

  factory EventStaff.fromJson(Map<String, dynamic> json) {
    // Profile data from join
    final profiles = json['profiles'] as Map<String, dynamic>?;

    return EventStaff(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String,
      role: StaffRole.fromString(json['role'] as String) ?? StaffRole.usher,
      invitedEmail: json['invited_email'] as String?,
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      userName: profiles?['display_name'] as String?,
      userEmail: profiles?['email'] as String? ?? json['invited_email'] as String?,
    );
  }

  bool get canSellTickets => role == StaffRole.seller || role == StaffRole.manager;
  bool get canCheckTickets => true; // All staff can check tickets
  bool get canManageStaff => role == StaffRole.manager;
}
