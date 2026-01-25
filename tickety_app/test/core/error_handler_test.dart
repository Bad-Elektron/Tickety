import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:tickety/core/errors/app_exception.dart';
import 'package:tickety/core/errors/error_handler.dart';

void main() {
  group('ErrorHandler.normalize', () {
    test('returns AppException unchanged', () {
      const original = NetworkException('Test');
      final result = ErrorHandler.normalize(original);

      expect(result, same(original));
    });

    test('converts SocketException to NetworkException', () {
      final error = SocketException('Connection refused');
      final result = ErrorHandler.normalize(error);

      expect(result, isA<NetworkException>());
      expect(result.message, contains('internet connection'));
    });

    test('converts TimeoutException to NetworkException', () {
      final error = TimeoutException('Request timed out');
      final result = ErrorHandler.normalize(error);

      expect(result, isA<NetworkException>());
      expect(result.message, contains('timed out'));
    });

    test('converts HttpException to NetworkException', () {
      final error = HttpException('500 Server Error');
      final result = ErrorHandler.normalize(error);

      expect(result, isA<NetworkException>());
      expect(result.message, contains('Server error'));
    });

    test('converts FormatException to ValidationException', () {
      final error = FormatException('Invalid JSON');
      final result = ErrorHandler.normalize(error);

      expect(result, isA<ValidationException>());
      expect(result.message, contains('Invalid data'));
    });

    test('converts StateError to BusinessException', () {
      final error = StateError('Invalid state');
      final result = ErrorHandler.normalize(error);

      expect(result, isA<BusinessException>());
    });

    test('converts unknown errors to UnknownException', () {
      final error = Exception('Random error');
      final result = ErrorHandler.normalize(error);

      expect(result, isA<UnknownException>());
      expect(result.message, contains('Something went wrong'));
    });

    test('converts Supabase AuthException', () {
      final error = supabase.AuthException('Invalid login credentials');
      final result = ErrorHandler.normalize(error);

      expect(result, isA<AuthException>());
    });

    test('converts Supabase PostgrestException with permission denied', () {
      final error = supabase.PostgrestException(
        message: 'Permission denied for table events',
        code: '42501',
      );
      final result = ErrorHandler.normalize(error);

      expect(result, isA<PermissionException>());
    });

    test('converts Supabase PostgrestException with no rows', () {
      final error = supabase.PostgrestException(
        message: 'No rows found',
        code: 'PGRST116',
      );
      final result = ErrorHandler.normalize(error);

      expect(result, isA<DataException>());
      expect(result.message, contains('not found'));
    });

    test('converts Supabase PostgrestException with duplicate key', () {
      final error = supabase.PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
      final result = ErrorHandler.normalize(error);

      expect(result, isA<DataException>());
      expect(result.message, contains('already exists'));
    });

    test('converts Supabase PostgrestException with foreign key violation', () {
      final error = supabase.PostgrestException(
        message: 'foreign key constraint violation',
        code: '23503',
      );
      final result = ErrorHandler.normalize(error);

      expect(result, isA<DataException>());
      expect(result.message, contains('not allowed'));
    });

    test('converts Supabase PostgrestException with not null violation', () {
      final error = supabase.PostgrestException(
        message: 'null value in column violates not-null constraint',
        code: '23502',
      );
      final result = ErrorHandler.normalize(error);

      expect(result, isA<ValidationException>());
      expect(result.message, contains('required'));
    });

    test('converts unknown Supabase PostgrestException to DataException', () {
      final error = supabase.PostgrestException(
        message: 'Some database error',
        code: '99999',
      );
      final result = ErrorHandler.normalize(error);

      expect(result, isA<DataException>());
      expect(result.message, contains('Database error'));
    });
  });

  group('ErrorHandler.tryAsync', () {
    test('returns result on success', () async {
      final result = await ErrorHandler.tryAsync(
        () async => 'success',
        operation: 'test operation',
      );

      expect(result, 'success');
    });

    test('returns null on error', () async {
      final result = await ErrorHandler.tryAsync<String>(
        () async => throw Exception('Failed'),
        operation: 'test operation',
      );

      expect(result, isNull);
    });

    test('returns fallback on error when provided', () async {
      final result = await ErrorHandler.tryAsync<String>(
        () async => throw Exception('Failed'),
        operation: 'test operation',
        fallback: 'default',
      );

      expect(result, 'default');
    });
  });

  group('ErrorHandler.wrapAsync', () {
    test('returns result on success', () async {
      final result = await ErrorHandler.wrapAsync(
        () async => 'success',
        operation: 'test operation',
      );

      expect(result, 'success');
    });

    test('throws AppException on error', () async {
      expect(
        () => ErrorHandler.wrapAsync(
          () async => throw Exception('Failed'),
          operation: 'test operation',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rethrows normalized AppException', () async {
      try {
        await ErrorHandler.wrapAsync(
          () async => throw SocketException('No connection'),
          operation: 'test operation',
        );
        fail('Should have thrown');
      } catch (e) {
        expect(e, isA<NetworkException>());
      }
    });
  });

  group('FutureErrorHandling extension', () {
    test('tryOrNull returns result on success', () async {
      final result = await Future.value('success').tryOrNull(
        operation: 'test',
      );

      expect(result, 'success');
    });

    test('tryOrNull returns null on error', () async {
      final result = await Future<String>.error(Exception('Failed')).tryOrNull(
        operation: 'test',
      );

      expect(result, isNull);
    });

    test('tryOr returns result on success', () async {
      final result = await Future.value('success').tryOr(
        'default',
        operation: 'test',
      );

      expect(result, 'success');
    });

    test('tryOr returns fallback on error', () async {
      final result = await Future<String>.error(Exception('Failed')).tryOr(
        'default',
        operation: 'test',
      );

      expect(result, 'default');
    });
  });
}
