import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../models/staff_role.dart';
import 'i_staff_repository.dart';

export 'i_staff_repository.dart' show UserSearchResult, IStaffRepository;

const _tag = 'StaffRepository';

/// Supabase implementation of [IStaffRepository].
class StaffRepository implements IStaffRepository {
  final _client = SupabaseService.instance.client;

  @override
  Future<List<UserSearchResult>> searchUsersByEmail(String emailQuery) async {
    if (emailQuery.trim().isEmpty) return [];

    AppLogger.debug('Searching users by email: $emailQuery', tag: _tag);

    final response = await _client
        .from('profiles')
        .select('id, email, display_name')
        .ilike('email', '%${emailQuery.trim()}%')
        .limit(10);

    final results = (response as List<dynamic>)
        .map((json) => UserSearchResult.fromJson(json as Map<String, dynamic>))
        .toList();

    AppLogger.debug('User search returned ${results.length} results', tag: _tag);
    return results;
  }

  @override
  Future<UserSearchResult?> getUserByEmail(String email) async {
    AppLogger.debug('Looking up user by email: $email', tag: _tag);

    final response = await _client
        .from('profiles')
        .select('id, email, display_name')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();

    if (response == null) {
      AppLogger.debug('User not found: $email', tag: _tag);
      return null;
    }
    return UserSearchResult.fromJson(response);
  }

  @override
  Future<List<EventStaff>> getEventStaff(String eventId) async {
    AppLogger.debug('Fetching staff for event: $eventId', tag: _tag);

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
      } catch (e) {
        AppLogger.warning(
          'Failed to fetch profile for user $userId',
          tag: _tag,
        );
        // Profile lookup failed, continue without it
      }

      // Merge profile data into staff record
      final enrichedStaff = {
        ...staff,
        'profiles': profile,
      };

      results.add(EventStaff.fromJson(enrichedStaff));
    }

    AppLogger.debug('Fetched ${results.length} staff members', tag: _tag);
    return results;
  }

  @override
  Future<EventStaff> addStaff({
    required String eventId,
    required String userId,
    required StaffRole role,
    String? email,
  }) async {
    AppLogger.debug(
      'Adding staff: userId=$userId, role=${role.value}, event=$eventId',
      tag: _tag,
    );

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

    AppLogger.info('Staff member added: ${response['id']}', tag: _tag);
    return EventStaff.fromJson(response);
  }

  @override
  Future<void> removeStaff(String staffId) async {
    AppLogger.debug('Removing staff: $staffId', tag: _tag);
    await _client.from('event_staff').delete().eq('id', staffId);
    AppLogger.info('Staff member removed: $staffId', tag: _tag);
  }

  @override
  Future<EventStaff> updateStaffRole(String staffId, StaffRole newRole) async {
    AppLogger.debug(
      'Updating staff role: $staffId -> ${newRole.value}',
      tag: _tag,
    );

    final response = await _client
        .from('event_staff')
        .update({'role': newRole.value})
        .eq('id', staffId)
        .select()
        .single();

    AppLogger.info('Staff role updated: $staffId', tag: _tag);
    return EventStaff.fromJson(response);
  }

  @override
  Future<EventStaff?> getCurrentUserStaffRole(String eventId) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.debug('No current user for staff role check', tag: _tag);
      return null;
    }

    AppLogger.debug(
      'Checking staff role for user $userId on event $eventId',
      tag: _tag,
    );

    final response = await _client
        .from('event_staff')
        .select()
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) {
      AppLogger.debug('User has no staff role on this event', tag: _tag);
      return null;
    }
    return EventStaff.fromJson(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getMyStaffEvents() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.debug('No current user for staff events', tag: _tag);
      return [];
    }

    AppLogger.debug('Fetching staff events for user: $userId', tag: _tag);

    final response = await _client
        .from('event_staff')
        .select('*, events(*)')
        .eq('user_id', userId);

    final results = (response as List<dynamic>).cast<Map<String, dynamic>>();
    AppLogger.debug('Found ${results.length} staff events', tag: _tag);
    return results;
  }

  @override
  Future<int> getStaffCount(String eventId) async {
    AppLogger.debug('Getting staff count for event: $eventId', tag: _tag);

    final response = await _client
        .from('event_staff')
        .select('id')
        .eq('event_id', eventId);

    final count = (response as List<dynamic>).length;
    AppLogger.debug('Staff count: $count', tag: _tag);
    return count;
  }
}
