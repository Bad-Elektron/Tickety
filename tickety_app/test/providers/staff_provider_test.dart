import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tickety/core/providers/staff_provider.dart';
import 'package:tickety/features/staff/data/i_staff_repository.dart';
import 'package:tickety/features/staff/models/staff_role.dart';

import '../mocks/mock_repositories.dart';

void main() {
  group('StaffState', () {
    test('initial state has empty values', () {
      const state = StaffState();

      expect(state.staff, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.currentEventId, isNull);
    });

    test('copyWith creates copy with modified values', () {
      const state = StaffState();
      final staff = [
        _createMockStaff('1', StaffRole.usher),
        _createMockStaff('2', StaffRole.seller),
      ];

      final modified = state.copyWith(
        staff: staff,
        isLoading: true,
        currentEventId: 'evt_001',
      );

      expect(modified.staff, staff);
      expect(modified.isLoading, isTrue);
      expect(modified.currentEventId, 'evt_001');
    });

    test('copyWith with clearError removes error', () {
      final state = const StaffState().copyWith(error: 'Some error');
      final cleared = state.copyWith(clearError: true);

      expect(cleared.error, isNull);
    });

    test('getByRole filters staff correctly', () {
      final staff = [
        _createMockStaff('1', StaffRole.usher),
        _createMockStaff('2', StaffRole.usher),
        _createMockStaff('3', StaffRole.seller),
        _createMockStaff('4', StaffRole.manager),
      ];
      final state = const StaffState().copyWith(staff: staff);

      expect(state.getByRole(StaffRole.usher).length, 2);
      expect(state.getByRole(StaffRole.seller).length, 1);
      expect(state.getByRole(StaffRole.manager).length, 1);
    });

    test('convenience getters return correct counts', () {
      final staff = [
        _createMockStaff('1', StaffRole.usher),
        _createMockStaff('2', StaffRole.usher),
        _createMockStaff('3', StaffRole.seller),
      ];
      final state = const StaffState().copyWith(staff: staff);

      expect(state.ushers.length, 2);
      expect(state.sellers.length, 1);
      expect(state.managers.length, 0);
      expect(state.usherCount, 2);
      expect(state.sellerCount, 1);
      expect(state.managerCount, 0);
      expect(state.totalCount, 3);
    });
  });

  group('StaffNotifier', () {
    late MockStaffRepository mockRepository;
    late StaffNotifier notifier;

    setUp(() {
      mockRepository = MockStaffRepository();
      notifier = StaffNotifier(mockRepository);
    });

    test('initial state is empty', () {
      expect(notifier.state.staff, isEmpty);
      expect(notifier.state.isLoading, isFalse);
    });

    test('loadStaff sets loading state and fetches staff', () async {
      final staff = [_createMockStaff('1', StaffRole.usher)];
      when(() => mockRepository.getEventStaff('evt_001'))
          .thenAnswer((_) async => staff);

      final future = notifier.loadStaff('evt_001');

      // Should be loading
      expect(notifier.state.isLoading, isTrue);
      expect(notifier.state.currentEventId, 'evt_001');

      await future;

      // Should have loaded
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.staff, staff);
      verify(() => mockRepository.getEventStaff('evt_001')).called(1);
    });

    test('loadStaff handles errors', () async {
      when(() => mockRepository.getEventStaff('evt_001'))
          .thenThrow(Exception('Network error'));

      await notifier.loadStaff('evt_001');

      expect(notifier.state.isLoading, isFalse);
      // Error is normalized to user-friendly message
      expect(notifier.state.error, isNotNull);
    });

    test('addStaff adds staff and updates state', () async {
      final newStaff = _createMockStaff('new_1', StaffRole.usher);

      // Set up current event
      when(() => mockRepository.getEventStaff('evt_001'))
          .thenAnswer((_) async => []);
      await notifier.loadStaff('evt_001');

      when(() => mockRepository.addStaff(
            eventId: 'evt_001',
            userId: 'user_001',
            role: StaffRole.usher,
            email: 'test@example.com',
          )).thenAnswer((_) async => newStaff);

      final result = await notifier.addStaff(
        userId: 'user_001',
        role: StaffRole.usher,
        email: 'test@example.com',
      );

      expect(result, isTrue);
      expect(notifier.state.staff.contains(newStaff), isTrue);
    });

    test('addStaff returns false when no event is set', () async {
      final result = await notifier.addStaff(
        userId: 'user_001',
        role: StaffRole.usher,
      );

      expect(result, isFalse);
    });

    test('removeStaff removes staff from state', () async {
      final staff = [
        _createMockStaff('1', StaffRole.usher),
        _createMockStaff('2', StaffRole.seller),
      ];

      when(() => mockRepository.getEventStaff('evt_001'))
          .thenAnswer((_) async => staff);
      await notifier.loadStaff('evt_001');

      when(() => mockRepository.removeStaff('1'))
          .thenAnswer((_) async {});

      final result = await notifier.removeStaff('1');

      expect(result, isTrue);
      expect(notifier.state.staff.length, 1);
      expect(notifier.state.staff.first.id, '2');
    });

    test('clear resets state', () async {
      final staff = [_createMockStaff('1', StaffRole.usher)];
      when(() => mockRepository.getEventStaff('evt_001'))
          .thenAnswer((_) async => staff);
      await notifier.loadStaff('evt_001');

      notifier.clear();

      expect(notifier.state.staff, isEmpty);
      expect(notifier.state.currentEventId, isNull);
    });

    test('clearError removes error from state', () async {
      when(() => mockRepository.getEventStaff('evt_001'))
          .thenThrow(Exception('Error'));
      await notifier.loadStaff('evt_001');

      expect(notifier.state.error, isNotNull);

      notifier.clearError();

      expect(notifier.state.error, isNull);
    });
  });

  group('UserSearchState', () {
    test('initial state is empty', () {
      const state = UserSearchState();

      expect(state.results, isEmpty);
      expect(state.isSearching, isFalse);
      expect(state.error, isNull);
    });

    test('copyWith creates modified copy', () {
      final results = [
        const UserSearchResult(id: '1', email: 'test@example.com'),
      ];

      final state = const UserSearchState().copyWith(
        results: results,
        isSearching: true,
      );

      expect(state.results, results);
      expect(state.isSearching, isTrue);
    });
  });

  group('UserSearchNotifier', () {
    late MockStaffRepository mockRepository;
    late UserSearchNotifier notifier;

    setUp(() {
      mockRepository = MockStaffRepository();
      notifier = UserSearchNotifier(mockRepository);
    });

    test('search returns empty for short queries', () async {
      await notifier.search('a');

      expect(notifier.state.results, isEmpty);
      verifyNever(() => mockRepository.searchUsersByEmail(any()));
    });

    test('search fetches results for valid query', () async {
      final results = [
        const UserSearchResult(id: '1', email: 'test@example.com'),
      ];

      when(() => mockRepository.searchUsersByEmail('test'))
          .thenAnswer((_) async => results);

      await notifier.search('test');

      expect(notifier.state.results, results);
      expect(notifier.state.isSearching, isFalse);
    });

    test('search returns all users without filtering', () async {
      final results = [
        const UserSearchResult(id: '1', email: 'user1@example.com'),
        const UserSearchResult(id: '2', email: 'user2@example.com'),
        const UserSearchResult(id: '3', email: 'user3@example.com'),
      ];

      when(() => mockRepository.searchUsersByEmail('user'))
          .thenAnswer((_) async => results);

      await notifier.search('user');

      // All results returned - filtering is now done at the UI level
      expect(notifier.state.results.length, 3);
    });

    test('clear resets state', () async {
      final results = [
        const UserSearchResult(id: '1', email: 'test@example.com'),
      ];
      when(() => mockRepository.searchUsersByEmail('test'))
          .thenAnswer((_) async => results);
      await notifier.search('test');

      notifier.clear();

      expect(notifier.state.results, isEmpty);
    });
  });
}

EventStaff _createMockStaff(String id, StaffRole role) {
  return EventStaff.fromJson({
    'id': id,
    'event_id': 'evt_001',
    'user_id': 'user_$id',
    'role': role.value,
    'created_at': '2025-01-15T10:00:00Z',
    'profiles': {'display_name': 'User $id', 'email': 'user$id@example.com'},
  });
}
