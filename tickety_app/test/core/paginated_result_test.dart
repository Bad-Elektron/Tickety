import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/core/models/paginated_result.dart';

void main() {
  group('PaginatedResult', () {
    test('creates with required values', () {
      final result = PaginatedResult<String>(
        items: ['a', 'b', 'c'],
        page: 0,
        pageSize: 10,
        hasMore: true,
      );

      expect(result.items, ['a', 'b', 'c']);
      expect(result.page, 0);
      expect(result.pageSize, 10);
      expect(result.hasMore, isTrue);
    });

    test('empty factory creates correct state', () {
      final result = PaginatedResult<int>.empty();

      expect(result.items, isEmpty);
      expect(result.page, 0);
      expect(result.pageSize, 20);
      expect(result.hasMore, isFalse);
    });

    test('empty factory accepts custom page and pageSize', () {
      final result = PaginatedResult<int>.empty(page: 2, pageSize: 50);

      expect(result.page, 2);
      expect(result.pageSize, 50);
    });

    test('isFirstPage returns true for page 0', () {
      final first = PaginatedResult<String>(
        items: ['a'],
        page: 0,
        pageSize: 10,
        hasMore: true,
      );
      final second = PaginatedResult<String>(
        items: ['b'],
        page: 1,
        pageSize: 10,
        hasMore: false,
      );

      expect(first.isFirstPage, isTrue);
      expect(second.isFirstPage, isFalse);
    });

    test('isEmpty returns true when items is empty', () {
      final empty = PaginatedResult<String>(
        items: [],
        page: 0,
        pageSize: 10,
        hasMore: false,
      );
      final notEmpty = PaginatedResult<String>(
        items: ['a'],
        page: 0,
        pageSize: 10,
        hasMore: false,
      );

      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);
      expect(notEmpty.isEmpty, isFalse);
      expect(notEmpty.isNotEmpty, isTrue);
    });

    test('length returns number of items', () {
      final result = PaginatedResult<String>(
        items: ['a', 'b', 'c'],
        page: 0,
        pageSize: 10,
        hasMore: true,
      );

      expect(result.length, 3);
    });

    test('copyWith creates copy with modified values', () {
      final original = PaginatedResult<String>(
        items: ['a'],
        page: 0,
        pageSize: 10,
        hasMore: true,
      );

      final modified = original.copyWith(
        items: ['b', 'c'],
        page: 1,
        hasMore: false,
      );

      expect(modified.items, ['b', 'c']);
      expect(modified.page, 1);
      expect(modified.pageSize, 10); // Unchanged
      expect(modified.hasMore, isFalse);
    });

    test('copyWith preserves values when not specified', () {
      final original = PaginatedResult<String>(
        items: ['a', 'b'],
        page: 2,
        pageSize: 25,
        hasMore: true,
      );

      final copy = original.copyWith();

      expect(copy.items, original.items);
      expect(copy.page, original.page);
      expect(copy.pageSize, original.pageSize);
      expect(copy.hasMore, original.hasMore);
    });

    test('toString provides readable format', () {
      final result = PaginatedResult<String>(
        items: ['a', 'b'],
        page: 1,
        pageSize: 20,
        hasMore: true,
      );

      expect(
        result.toString(),
        'PaginatedResult(page: 1, pageSize: 20, items: 2, hasMore: true)',
      );
    });
  });
}
