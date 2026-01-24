import '../../../core/services/services.dart';
import '../models/staff_role.dart';

/// Simple user data for staff assignment.
class UserSearchResult {
  final String id;
  final String email;
  final String? displayName;

  const UserSearchResult({
    required this.id,
    required this.email,
    this.displayName,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
    );
  }

  String get displayLabel => displayName ?? email;
}

/// Repository for staff operations.
class StaffRepository {
  final _client = SupabaseService.instance.client;

  /// Search for users by email (for adding staff).
  /// Returns users matching the email pattern from the profiles table.
  Future<List<UserSearchResult>> searchUsersByEmail(String emailQuery) async {
    if (emailQuery.trim().isEmpty) return [];

    final response = await _client
        .from('profiles')
        .select('id, email, display_name')
        .ilike('email', '%${emailQuery.trim()}%')
        .limit(10);

    return (response as List<dynamic>)
        .map((json) => UserSearchResult.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get a user by exact email address.
  Future<UserSearchResult?> getUserByEmail(String email) async {
    final response = await _client
        .from('profiles')
        .select('id, email, display_name')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();

    if (response == null) return null;
    return UserSearchResult.fromJson(response);
  }

  /// Get all staff for an event.
  Future<List<EventStaff>> getEventStaff(String eventId) async {
    // First get the staff assignments
    final response = await _client
        .from('event_staff')
        .select()
        .eq('event_id', eventId)
        .order('created_at', ascending: false);

    final staffList = (response as List<dynamic>).cast<Map<String, dynamic>>();

    // Then fetch profile info for each user
    final results = <EventStaff>[];
    for (final staff in staffList) {
      final userId = staff['user_id'] as String;

      // Try to get profile info
      Map<String, dynamic>? profile;
      try {
        profile = await _client
            .from('profiles')
            .select('display_name, email')
            .eq('id', userId)
            .maybeSingle();
      } catch (_) {
        // Profile lookup failed, continue without it
      }

      // Merge profile data into staff record
      final enrichedStaff = {
        ...staff,
        'profiles': profile,
      };

      results.add(EventStaff.fromJson(enrichedStaff));
    }

    return results;
  }

  /// Add staff to an event.
  Future<EventStaff> addStaff({
    required String eventId,
    required String userId,
    required StaffRole role,
    String? email,
  }) async {
    final response = await _client
        .from('event_staff')
        .insert({
          'event_id': eventId,
          'user_id': userId,
          'role': role.value,
          'invited_email': email,
        })
        .select()
        .single();

    return EventStaff.fromJson(response);
  }

  /// Remove staff from an event.
  Future<void> removeStaff(String staffId) async {
    await _client.from('event_staff').delete().eq('id', staffId);
  }

  /// Update staff role.
  Future<EventStaff> updateStaffRole(String staffId, StaffRole newRole) async {
    final response = await _client
        .from('event_staff')
        .update({'role': newRole.value})
        .eq('id', staffId)
        .select()
        .single();

    return EventStaff.fromJson(response);
  }

  /// Check if current user is staff for an event.
  Future<EventStaff?> getCurrentUserStaffRole(String eventId) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return null;

    final response = await _client
        .from('event_staff')
        .select()
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return EventStaff.fromJson(response);
  }

  /// Get all events where current user is staff.
  Future<List<Map<String, dynamic>>> getMyStaffEvents() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('event_staff')
        .select('*, events(*)')
        .eq('user_id', userId);

    return (response as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// Get staff count for an event.
  Future<int> getStaffCount(String eventId) async {
    final response = await _client
        .from('event_staff')
        .select('id')
        .eq('event_id', eventId);

    return (response as List<dynamic>).length;
  }
}
