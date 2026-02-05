/// Staff roles for event management.
enum StaffRole {
  usher('usher', 'Usher', 'Can check tickets at entry'),
  seller('seller', 'Seller', 'Can sell tickets on the spot'),
  manager('manager', 'Manager', 'Can check tickets, sell, and manage staff');

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
    // Profile data from join - handle both nested object and null cases
    final profilesRaw = json['profiles'];
    Map<String, dynamic>? profiles;
    if (profilesRaw is Map<String, dynamic>) {
      profiles = profilesRaw;
    }

    // Safely parse required fields with better error messages
    final id = json['id'];
    final eventId = json['event_id'];
    final oderId = json['user_id'];
    final createdAt = json['created_at'];

    if (id == null || eventId == null || oderId == null || createdAt == null) {
      throw FormatException(
        'Missing required fields in EventStaff JSON. '
        'id=$id, event_id=$eventId, user_id=$oderId, created_at=$createdAt. '
        'Full JSON: $json',
      );
    }

    return EventStaff(
      id: id as String,
      eventId: eventId as String,
      userId: oderId as String,
      role: StaffRole.fromString(json['role'] as String?) ?? StaffRole.usher,
      invitedEmail: json['invited_email'] as String?,
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      createdAt: DateTime.parse(createdAt as String),
      userName: profiles?['display_name'] as String?,
      userEmail: profiles?['email'] as String? ?? json['invited_email'] as String?,
    );
  }

  bool get canSellTickets => role == StaffRole.seller || role == StaffRole.manager;
  bool get canCheckTickets => true; // All staff can check tickets
  bool get canManageStaff => role == StaffRole.manager;

  EventStaff copyWith({
    String? id,
    String? eventId,
    String? userId,
    StaffRole? role,
    String? invitedEmail,
    DateTime? acceptedAt,
    DateTime? createdAt,
    String? userName,
    String? userEmail,
  }) {
    return EventStaff(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      invitedEmail: invitedEmail ?? this.invitedEmail,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      createdAt: createdAt ?? this.createdAt,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
    );
  }
}
