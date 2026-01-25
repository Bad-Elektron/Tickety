import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/features/staff/data/i_staff_repository.dart';

void main() {
  group('UserSearchResult', () {
    test('creates with required fields', () {
      const result = UserSearchResult(
        id: 'user_001',
        email: 'test@example.com',
      );

      expect(result.id, 'user_001');
      expect(result.email, 'test@example.com');
      expect(result.displayName, isNull);
    });

    test('creates with all fields', () {
      const result = UserSearchResult(
        id: 'user_001',
        email: 'test@example.com',
        displayName: 'John Doe',
      );

      expect(result.id, 'user_001');
      expect(result.email, 'test@example.com');
      expect(result.displayName, 'John Doe');
    });

    group('fromJson', () {
      test('parses complete JSON', () {
        final json = {
          'id': 'user_001',
          'email': 'test@example.com',
          'display_name': 'John Doe',
        };

        final result = UserSearchResult.fromJson(json);

        expect(result.id, 'user_001');
        expect(result.email, 'test@example.com');
        expect(result.displayName, 'John Doe');
      });

      test('parses JSON without display_name', () {
        final json = {
          'id': 'user_002',
          'email': 'user2@example.com',
        };

        final result = UserSearchResult.fromJson(json);

        expect(result.id, 'user_002');
        expect(result.email, 'user2@example.com');
        expect(result.displayName, isNull);
      });

      test('handles null display_name', () {
        final json = {
          'id': 'user_003',
          'email': 'user3@example.com',
          'display_name': null,
        };

        final result = UserSearchResult.fromJson(json);

        expect(result.displayName, isNull);
      });
    });

    group('displayLabel', () {
      test('returns displayName when available', () {
        const result = UserSearchResult(
          id: 'user_001',
          email: 'test@example.com',
          displayName: 'John Doe',
        );

        expect(result.displayLabel, 'John Doe');
      });

      test('returns email when displayName is null', () {
        const result = UserSearchResult(
          id: 'user_001',
          email: 'test@example.com',
        );

        expect(result.displayLabel, 'test@example.com');
      });

      test('prefers displayName over email', () {
        const result = UserSearchResult(
          id: 'user_001',
          email: 'test@example.com',
          displayName: 'Test User',
        );

        expect(result.displayLabel, 'Test User');
        expect(result.displayLabel, isNot('test@example.com'));
      });
    });

    group('equality', () {
      test('instances with same values are equal when using const', () {
        const result1 = UserSearchResult(
          id: 'user_001',
          email: 'test@example.com',
          displayName: 'John',
        );
        const result2 = UserSearchResult(
          id: 'user_001',
          email: 'test@example.com',
          displayName: 'John',
        );

        // Const instances are identical
        expect(identical(result1, result2), isTrue);
      });
    });

    group('edge cases', () {
      test('handles empty email', () {
        const result = UserSearchResult(
          id: 'user_001',
          email: '',
        );

        expect(result.email, '');
        expect(result.displayLabel, '');
      });

      test('handles empty displayName', () {
        const result = UserSearchResult(
          id: 'user_001',
          email: 'test@example.com',
          displayName: '',
        );

        // Empty string is still truthy, so it's used
        expect(result.displayLabel, '');
      });

      test('handles special characters in email', () {
        const result = UserSearchResult(
          id: 'user_001',
          email: 'test+special@example.com',
        );

        expect(result.email, 'test+special@example.com');
        expect(result.displayLabel, 'test+special@example.com');
      });

      test('handles unicode in displayName', () {
        const result = UserSearchResult(
          id: 'user_001',
          email: 'test@example.com',
          displayName: 'José García',
        );

        expect(result.displayName, 'José García');
        expect(result.displayLabel, 'José García');
      });
    });
  });
}
