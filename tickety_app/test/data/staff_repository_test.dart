import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/staff/data/staff_repository.dart';
import 'package:tickety/features/staff/models/staff_role.dart';

void main() {
  group('StaffRepository', () {
    group('EventStaff.fromJson', () {
      test('correctly parses staff with profile data', () {
        final json = {
          'id': 'staff-123',
          'event_id': 'event-456',
          'user_id': 'user-789',
          'role': 'usher',
          'invited_email': 'test@example.com',
          'created_at': '2025-01-26T10:00:00Z',
          'profiles': {
            'display_name': 'Test User',
            'email': 'test@example.com',
          },
        };

        final staff = EventStaff.fromJson(json);

        expect(staff.id, 'staff-123');
        expect(staff.eventId, 'event-456');
        expect(staff.userId, 'user-789');
        expect(staff.role, StaffRole.usher);
        expect(staff.userName, 'Test User');
        expect(staff.userEmail, 'test@example.com');
      });

      test('correctly parses staff without profile data', () {
        final json = {
          'id': 'staff-123',
          'event_id': 'event-456',
          'user_id': 'user-789',
          'role': 'seller',
          'invited_email': 'seller@example.com',
          'created_at': '2025-01-26T10:00:00Z',
        };

        final staff = EventStaff.fromJson(json);

        expect(staff.id, 'staff-123');
        expect(staff.role, StaffRole.seller);
        expect(staff.userName, isNull);
        expect(staff.userEmail, 'seller@example.com'); // Falls back to invited_email
      });

      test('correctly parses staff with null profiles', () {
        final json = {
          'id': 'staff-123',
          'event_id': 'event-456',
          'user_id': 'user-789',
          'role': 'manager',
          'created_at': '2025-01-26T10:00:00Z',
          'profiles': null,
        };

        final staff = EventStaff.fromJson(json);

        expect(staff.id, 'staff-123');
        expect(staff.role, StaffRole.manager);
        expect(staff.userName, isNull);
        expect(staff.userEmail, isNull);
      });

      test('correctly parses staff with partial profile data', () {
        final json = {
          'id': 'staff-123',
          'event_id': 'event-456',
          'user_id': 'user-789',
          'role': 'usher',
          'invited_email': 'fallback@example.com',
          'created_at': '2025-01-26T10:00:00Z',
          'profiles': {
            'display_name': 'Partial User',
            // email is missing
          },
        };

        final staff = EventStaff.fromJson(json);

        expect(staff.userName, 'Partial User');
        expect(staff.userEmail, 'fallback@example.com'); // Falls back to invited_email
      });

      test('throws FormatException when required fields are missing', () {
        final json = {
          'id': 'staff-123',
          // missing event_id, user_id, created_at
        };

        expect(
          () => EventStaff.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      test('defaults to usher role for invalid role value', () {
        final json = {
          'id': 'staff-123',
          'event_id': 'event-456',
          'user_id': 'user-789',
          'role': 'invalid_role',
          'created_at': '2025-01-26T10:00:00Z',
        };

        final staff = EventStaff.fromJson(json);

        expect(staff.role, StaffRole.usher);
      });

      test('correctly parses acceptedAt date', () {
        final json = {
          'id': 'staff-123',
          'event_id': 'event-456',
          'user_id': 'user-789',
          'role': 'usher',
          'accepted_at': '2025-01-27T14:30:00Z',
          'created_at': '2025-01-26T10:00:00Z',
        };

        final staff = EventStaff.fromJson(json);

        expect(staff.acceptedAt, isNotNull);
        expect(staff.acceptedAt!.year, 2025);
        expect(staff.acceptedAt!.month, 1);
        expect(staff.acceptedAt!.day, 27);
      });
    });

    group('UserSearchResult.fromJson', () {
      test('correctly parses user search result', () {
        final json = {
          'id': 'user-123',
          'email': 'test@example.com',
          'display_name': 'Test User',
        };

        final result = UserSearchResult.fromJson(json);

        expect(result.id, 'user-123');
        expect(result.email, 'test@example.com');
        expect(result.displayName, 'Test User');
        expect(result.displayLabel, 'Test User');
      });

      test('displayLabel falls back to email when displayName is null', () {
        final json = {
          'id': 'user-123',
          'email': 'test@example.com',
          'display_name': null,
        };

        final result = UserSearchResult.fromJson(json);

        expect(result.displayName, isNull);
        expect(result.displayLabel, 'test@example.com');
      });
    });

    group('Staff permissions', () {
      late EventStaff usher;
      late EventStaff seller;
      late EventStaff manager;

      setUp(() {
        usher = EventStaff.fromJson({
          'id': 'usher-1',
          'event_id': 'event-1',
          'user_id': 'user-1',
          'role': 'usher',
          'created_at': '2025-01-26T10:00:00Z',
        });
        seller = EventStaff.fromJson({
          'id': 'seller-1',
          'event_id': 'event-1',
          'user_id': 'user-2',
          'role': 'seller',
          'created_at': '2025-01-26T10:00:00Z',
        });
        manager = EventStaff.fromJson({
          'id': 'manager-1',
          'event_id': 'event-1',
          'user_id': 'user-3',
          'role': 'manager',
          'created_at': '2025-01-26T10:00:00Z',
        });
      });

      test('canSellTickets is correct for each role', () {
        expect(usher.canSellTickets, isFalse);
        expect(seller.canSellTickets, isTrue);
        expect(manager.canSellTickets, isTrue);
      });

      test('canCheckTickets is true for all staff', () {
        expect(usher.canCheckTickets, isTrue);
        expect(seller.canCheckTickets, isTrue);
        expect(manager.canCheckTickets, isTrue);
      });

      test('canManageStaff is only true for manager', () {
        expect(usher.canManageStaff, isFalse);
        expect(seller.canManageStaff, isFalse);
        expect(manager.canManageStaff, isTrue);
      });
    });

    group('StaffRole enum', () {
      test('all roles have correct values', () {
        expect(StaffRole.usher.value, 'usher');
        expect(StaffRole.seller.value, 'seller');
        expect(StaffRole.manager.value, 'manager');
      });

      test('all roles have labels', () {
        expect(StaffRole.usher.label, isNotEmpty);
        expect(StaffRole.seller.label, isNotEmpty);
        expect(StaffRole.manager.label, isNotEmpty);
      });

      test('all roles have descriptions', () {
        expect(StaffRole.usher.description, isNotEmpty);
        expect(StaffRole.seller.description, isNotEmpty);
        expect(StaffRole.manager.description, isNotEmpty);
      });

      test('fromString parses all valid roles', () {
        expect(StaffRole.fromString('usher'), StaffRole.usher);
        expect(StaffRole.fromString('seller'), StaffRole.seller);
        expect(StaffRole.fromString('manager'), StaffRole.manager);
      });

      test('fromString returns null for invalid values', () {
        expect(StaffRole.fromString('invalid'), isNull);
        expect(StaffRole.fromString(''), isNull);
        expect(StaffRole.fromString(null), isNull);
      });
    });

    group('Staff data merge logic', () {
      test('profile data is correctly merged with staff data', () {
        // Simulates the manual merge that happens in getEventStaff
        final staffJson = {
          'id': 'staff-1',
          'event_id': 'event-1',
          'user_id': 'user-1',
          'role': 'usher',
          'invited_email': 'invited@example.com',
          'created_at': '2025-01-26T10:00:00Z',
        };

        final profileData = {
          'display_name': 'John Doe',
          'email': 'john@example.com',
        };

        // Merge like the repository does
        final mergedJson = Map<String, dynamic>.from(staffJson);
        mergedJson['profiles'] = profileData;

        final staff = EventStaff.fromJson(mergedJson);

        expect(staff.userName, 'John Doe');
        expect(staff.userEmail, 'john@example.com');
        expect(staff.invitedEmail, 'invited@example.com');
      });

      test('handles multiple staff with different profile statuses', () {
        final staffList = [
          {
            'id': 'staff-1',
            'event_id': 'event-1',
            'user_id': 'user-1',
            'role': 'usher',
            'created_at': '2025-01-26T10:00:00Z',
            'profiles': {'display_name': 'User 1', 'email': 'user1@example.com'},
          },
          {
            'id': 'staff-2',
            'event_id': 'event-1',
            'user_id': 'user-2',
            'role': 'seller',
            'invited_email': 'seller@example.com',
            'created_at': '2025-01-26T11:00:00Z',
            // No profiles - user might not have created account yet
          },
          {
            'id': 'staff-3',
            'event_id': 'event-1',
            'user_id': 'user-3',
            'role': 'manager',
            'created_at': '2025-01-26T12:00:00Z',
            'profiles': null,
          },
        ];

        final results = staffList.map((json) => EventStaff.fromJson(json)).toList();

        // Staff 1: Has full profile
        expect(results[0].userName, 'User 1');
        expect(results[0].userEmail, 'user1@example.com');

        // Staff 2: No profile, falls back to invited_email
        expect(results[1].userName, isNull);
        expect(results[1].userEmail, 'seller@example.com');

        // Staff 3: Null profile
        expect(results[2].userName, isNull);
        expect(results[2].userEmail, isNull);
      });
    });
  });
}
