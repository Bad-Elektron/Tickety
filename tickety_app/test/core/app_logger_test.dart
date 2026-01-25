import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/core/errors/app_logger.dart';

void main() {
  setUp(() {
    // Clear any previous state before each test
    AppLogger.clearRecentLogs();
    AppLogger.setRemoteLogger(null);
  });

  group('LogLevel', () {
    test('levels are ordered correctly', () {
      expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
      expect(LogLevel.info.index, lessThan(LogLevel.warning.index));
      expect(LogLevel.warning.index, lessThan(LogLevel.error.index));
    });
  });

  group('AppLogger basic logging', () {
    test('debug logs message', () {
      // Should not throw
      AppLogger.debug('Debug message');
      AppLogger.debug('Debug with tag', tag: 'TestTag');
    });

    test('info logs message', () {
      AppLogger.info('Info message');
      AppLogger.info('Info with tag', tag: 'TestTag');
    });

    test('warning logs message', () {
      AppLogger.warning('Warning message');
      AppLogger.warning('Warning with tag', tag: 'TestTag');
    });

    test('error logs message with optional error and stack trace', () {
      AppLogger.error('Error message');
      AppLogger.error(
        'Error with details',
        error: Exception('Test error'),
        stackTrace: StackTrace.current,
        tag: 'TestTag',
      );
    });
  });

  group('AppLogger.recentLogs', () {
    test('stores recent log entries', () {
      AppLogger.info('Test log 1');
      AppLogger.info('Test log 2');
      AppLogger.warning('Test log 3');

      final logs = AppLogger.recentLogs;

      expect(logs.length, greaterThanOrEqualTo(3));
      expect(logs.any((log) => log.contains('Test log 1')), isTrue);
      expect(logs.any((log) => log.contains('Test log 2')), isTrue);
      expect(logs.any((log) => log.contains('Test log 3')), isTrue);
    });

    test('includes level in log entries', () {
      AppLogger.debug('Debug test');
      AppLogger.info('Info test');
      AppLogger.warning('Warning test');
      AppLogger.error('Error test');

      final logs = AppLogger.recentLogs;

      expect(logs.any((log) => log.contains('DEBUG')), isTrue);
      expect(logs.any((log) => log.contains('INFO')), isTrue);
      // LogLevel uses 'WARN' not 'WARNING'
      expect(logs.any((log) => log.contains('WARN')), isTrue);
      expect(logs.any((log) => log.contains('ERROR')), isTrue);
    });

    test('includes tag when provided', () {
      AppLogger.info('Tagged message', tag: 'MyComponent');

      final logs = AppLogger.recentLogs;

      expect(logs.any((log) => log.contains('MyComponent')), isTrue);
    });

    test('clearRecentLogs clears the buffer', () {
      AppLogger.info('Test log');
      expect(AppLogger.recentLogs, isNotEmpty);

      AppLogger.clearRecentLogs();

      expect(AppLogger.recentLogs, isEmpty);
    });

    test('respects max buffer size', () {
      // Log many entries to exceed buffer
      for (var i = 0; i < 150; i++) {
        AppLogger.debug('Log entry $i');
      }

      final logs = AppLogger.recentLogs;

      // Buffer should be capped at 100
      expect(logs.length, lessThanOrEqualTo(100));
    });
  });

  group('AppLogger.setRemoteLogger', () {
    test('calls remote logger when set', () {
      final capturedLogs = <Map<String, dynamic>>[];

      AppLogger.setRemoteLogger((level, message, error, stackTrace, tag) {
        capturedLogs.add({
          'level': level,
          'message': message,
          'error': error,
          'tag': tag,
        });
      });

      AppLogger.info('Remote test', tag: 'TestTag');

      expect(capturedLogs.length, 1);
      expect(capturedLogs.first['level'], LogLevel.info);
      expect(capturedLogs.first['message'], 'Remote test');
      expect(capturedLogs.first['tag'], 'TestTag');
    });

    test('remote logger receives error details', () {
      Map<String, dynamic>? capturedLog;

      AppLogger.setRemoteLogger((level, message, error, stackTrace, tag) {
        capturedLog = {
          'level': level,
          'message': message,
          'error': error,
          'stackTrace': stackTrace,
        };
      });

      final testError = Exception('Test exception');
      final testStack = StackTrace.current;

      AppLogger.error(
        'Error with details',
        error: testError,
        stackTrace: testStack,
      );

      expect(capturedLog, isNotNull);
      expect(capturedLog!['level'], LogLevel.error);
      expect(capturedLog!['error'], testError);
      expect(capturedLog!['stackTrace'], testStack);
    });

    test('can clear remote logger', () {
      var callCount = 0;

      AppLogger.setRemoteLogger((_, __, ___, ____, _____) {
        callCount++;
      });

      AppLogger.info('First log');
      expect(callCount, 1);

      AppLogger.setRemoteLogger(null);

      AppLogger.info('Second log');
      expect(callCount, 1); // Should not have increased
    });
  });

  group('AppLogger timestamp', () {
    test('includes timestamp in log entries', () {
      AppLogger.info('Timestamped log');

      final logs = AppLogger.recentLogs;
      final lastLog = logs.last;

      // Should contain ISO-like timestamp pattern
      expect(
        RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(lastLog),
        isTrue,
        reason: 'Log should contain date',
      );
    });
  });

  group('AppLogger.maskEmail', () {
    test('masks standard email correctly', () {
      expect(AppLogger.maskEmail('john.doe@example.com'), 'j***@example.com');
      expect(AppLogger.maskEmail('alice@test.co'), 'a***@test.co');
      expect(AppLogger.maskEmail('bob@company.org'), 'b***@company.org');
    });

    test('handles short usernames', () {
      expect(AppLogger.maskEmail('a@test.com'), 'a***@test.com');
      expect(AppLogger.maskEmail('ab@test.com'), 'a***@test.com');
    });

    test('handles null input', () {
      expect(AppLogger.maskEmail(null), 'null');
    });

    test('handles empty string', () {
      expect(AppLogger.maskEmail(''), '');
    });

    test('handles invalid email format', () {
      expect(AppLogger.maskEmail('notanemail'), '***');
      expect(AppLogger.maskEmail('@nodomain'), '***');
    });

    test('preserves domain information', () {
      final masked = AppLogger.maskEmail('test@subdomain.example.com');
      expect(masked, 't***@subdomain.example.com');
      expect(masked.contains('subdomain.example.com'), isTrue);
    });
  });
}
