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

/// Abstract repository interface for staff operations.
///
/// Defines the contract for managing event staff (ushers, sellers, managers).
/// Implementations can use different data sources (Supabase, mock, etc).
abstract class IStaffRepository {
  /// Search for users by email (for adding staff).
  /// Returns users matching the email pattern from the profiles table.
  Future<List<UserSearchResult>> searchUsersByEmail(String emailQuery);

  /// Get a user by exact email address.
  Future<UserSearchResult?> getUserByEmail(String email);

  /// Get all staff for an event.
  Future<List<EventStaff>> getEventStaff(String eventId);

  /// Add staff to an event.
  Future<EventStaff> addStaff({
    required String eventId,
    required String userId,
    required StaffRole role,
    String? email,
  });

  /// Remove staff from an event.
  Future<void> removeStaff(String staffId);

  /// Update staff role.
  Future<EventStaff> updateStaffRole(String staffId, StaffRole newRole);

  /// Check if current user is staff for an event.
  Future<EventStaff?> getCurrentUserStaffRole(String eventId);

  /// Get all events where current user is staff.
  Future<List<Map<String, dynamic>>> getMyStaffEvents();

  /// Get staff count for an event.
  Future<int> getStaffCount(String eventId);
}
