import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/staff/models/staff_role.dart';

void main() {
  group('StaffRole', () {
    test('fromString parses valid roles', () {
      expect(StaffRole.fromString('usher'), StaffRole.usher);
      expect(StaffRole.fromString('seller'), StaffRole.seller);
      expect(StaffRole.fromString('manager'), StaffRole.manager);
    });

    test('fromString returns null for unknown role', () {
      expect(StaffRole.fromString('unknown'), isNull);
      expect(StaffRole.fromString(null), isNull);
      expect(StaffRole.fromString(''), isNull);
    });

    test('value returns correct string', () {
      expect(StaffRole.usher.value, 'usher');
      expect(StaffRole.seller.value, 'seller');
      expect(StaffRole.manager.value, 'manager');
    });

    test('label returns human-readable name', () {
      expect(StaffRole.usher.label, 'Usher');
      expect(StaffRole.seller.label, 'Seller');
      expect(StaffRole.manager.label, 'Manager');
    });

    test('description returns role description', () {
      expect(StaffRole.usher.description, contains('check'));
      expect(StaffRole.seller.description, contains('sell'));
      expect(StaffRole.manager.description, contains('Full'));
    });
  });

  group('EventStaff', () {
    late Map<String, dynamic> validJson;

    setUp(() {
      validJson = {
        'id': 'staff_001',
        'event_id': 'evt_001',
        'user_id': 'user_001',
        'role': 'usher',
        'invited_email': 'test@example.com',
        'created_at': '2025-01-15T10:00:00Z',
        'profiles': {
          'display_name': 'John Doe',
          'email': 'john@example.com',
        },
      };
    });

    test('fromJson creates valid EventStaff', () {
      final staff = EventStaff.fromJson(validJson);

      expect(staff.id, 'staff_001');
      expect(staff.eventId, 'evt_001');
      expect(staff.userId, 'user_001');
      expect(staff.role, StaffRole.usher);
      expect(staff.invitedEmail, 'test@example.com');
    });

    test('userName uses profile display_name when available', () {
      final staff = EventStaff.fromJson(validJson);
      expect(staff.userName, 'John Doe');
    });

    test('userName is null when profile has no display_name', () {
      final jsonNoDisplayName = {
        ...validJson,
        'profiles': {
          'email': 'john@example.com',
        },
      };
      final staff = EventStaff.fromJson(jsonNoDisplayName);
      expect(staff.userName, isNull);
    });

    test('userEmail uses profile email when available', () {
      final staff = EventStaff.fromJson(validJson);
      expect(staff.userEmail, 'john@example.com');
    });

    test('userEmail falls back to invited_email', () {
      final jsonNoProfileEmail = {
        ...validJson,
        'profiles': {
          'display_name': 'John Doe',
        },
      };
      final staff = EventStaff.fromJson(jsonNoProfileEmail);
      expect(staff.userEmail, 'test@example.com');
    });

    test('userEmail is null when no profile or invited_email', () {
      final jsonMinimal = {
        'id': 'staff_002',
        'event_id': 'evt_001',
        'user_id': 'user_002',
        'role': 'usher',
        'created_at': '2025-01-15T10:00:00Z',
      };
      final staff = EventStaff.fromJson(jsonMinimal);
      expect(staff.userEmail, isNull);
    });

    test('canSellTickets is true for seller and manager', () {
      final usher = EventStaff.fromJson({...validJson, 'role': 'usher'});
      final seller = EventStaff.fromJson({...validJson, 'role': 'seller'});
      final manager = EventStaff.fromJson({...validJson, 'role': 'manager'});

      expect(usher.canSellTickets, isFalse);
      expect(seller.canSellTickets, isTrue);
      expect(manager.canSellTickets, isTrue);
    });

    test('canCheckTickets is true for all roles', () {
      final usher = EventStaff.fromJson({...validJson, 'role': 'usher'});
      final seller = EventStaff.fromJson({...validJson, 'role': 'seller'});
      final manager = EventStaff.fromJson({...validJson, 'role': 'manager'});

      expect(usher.canCheckTickets, isTrue);
      expect(seller.canCheckTickets, isTrue);
      expect(manager.canCheckTickets, isTrue);
    });

    test('canManageStaff is true only for manager', () {
      final usher = EventStaff.fromJson({...validJson, 'role': 'usher'});
      final seller = EventStaff.fromJson({...validJson, 'role': 'seller'});
      final manager = EventStaff.fromJson({...validJson, 'role': 'manager'});

      expect(usher.canManageStaff, isFalse);
      expect(seller.canManageStaff, isFalse);
      expect(manager.canManageStaff, isTrue);
    });

    test('fromJson handles null profiles gracefully', () {
      final jsonNullProfiles = {
        'id': 'staff_003',
        'event_id': 'evt_001',
        'user_id': 'user_003',
        'role': 'seller',
        'created_at': '2025-01-15T10:00:00Z',
        'profiles': null,
      };
      final staff = EventStaff.fromJson(jsonNullProfiles);

      expect(staff.id, 'staff_003');
      expect(staff.userName, isNull);
      expect(staff.userEmail, isNull);
    });

    test('fromJson handles missing profiles key', () {
      final jsonNoProfiles = {
        'id': 'staff_004',
        'event_id': 'evt_001',
        'user_id': 'user_004',
        'role': 'manager',
        'created_at': '2025-01-15T10:00:00Z',
      };
      final staff = EventStaff.fromJson(jsonNoProfiles);

      expect(staff.id, 'staff_004');
      expect(staff.role, StaffRole.manager);
      expect(staff.userName, isNull);
    });

    test('fromJson throws FormatException for missing required fields', () {
      expect(
        () => EventStaff.fromJson({'id': 'only_id'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson handles empty profiles object', () {
      final jsonEmptyProfiles = {
        'id': 'staff_005',
        'event_id': 'evt_001',
        'user_id': 'user_005',
        'role': 'usher',
        'created_at': '2025-01-15T10:00:00Z',
        'profiles': <String, dynamic>{},
      };
      final staff = EventStaff.fromJson(jsonEmptyProfiles);

      expect(staff.id, 'staff_005');
      expect(staff.userName, isNull);
      expect(staff.userEmail, isNull);
    });

    test('fromJson handles acceptedAt date', () {
      final jsonWithAccepted = {
        ...validJson,
        'accepted_at': '2025-01-16T14:30:00Z',
      };
      final staff = EventStaff.fromJson(jsonWithAccepted);

      expect(staff.acceptedAt, isNotNull);
      expect(staff.acceptedAt!.year, 2025);
      expect(staff.acceptedAt!.month, 1);
      expect(staff.acceptedAt!.day, 16);
    });

    test('fromJson defaults to usher role for unknown role value', () {
      final jsonUnknownRole = {
        ...validJson,
        'role': 'unknown_role',
      };
      final staff = EventStaff.fromJson(jsonUnknownRole);

      expect(staff.role, StaffRole.usher);
    });
  });
}
