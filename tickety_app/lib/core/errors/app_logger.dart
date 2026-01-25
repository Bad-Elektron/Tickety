import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Log levels for categorizing messages.
enum LogLevel {
  debug(0, 'DEBUG'),
  info(1, 'INFO'),
  warning(2, 'WARN'),
  error(3, 'ERROR');

  const LogLevel(this.priority, this.label);
  final int priority;
  final String label;
}

/// Centralized logging service for the app.
///
/// Usage:
/// ```dart
/// AppLogger.info('User logged in', tag: 'Auth');
/// AppLogger.error('Failed to load events', error: e, stackTrace: s, tag: 'Events');
/// ```
///
/// In production, this can be extended to send logs to a remote service
/// like Sentry, Crashlytics, or a custom backend.
class AppLogger {
  AppLogger._();

  /// Mask an email address for safe logging.
  ///
  /// Examples:
  /// - "john.doe@example.com" -> "j***@example.com"
  /// - "ab@test.co" -> "a***@test.co"
  /// - null -> "null"
  /// - "" -> ""
  static String maskEmail(String? email) {
    if (email == null) return 'null';
    if (email.isEmpty) return '';

    final atIndex = email.indexOf('@');
    if (atIndex <= 0) return '***'; // Invalid email format

    // Show first character, mask the rest before @
    final firstChar = email[0];
    final domain = email.substring(atIndex);
    return '$firstChar***$domain';
  }

  /// Minimum log level to output. Logs below this level are ignored.
  /// In release mode, defaults to warning. In debug, shows all.
  static LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.warning;

  /// Buffer of recent logs for crash reports.
  static final List<_LogEntry> _recentLogs = [];
  static const int _maxBufferSize = 100;

  /// Optional callback for remote logging services.
  static void Function(LogLevel level, String message, Object? error,
      StackTrace? stackTrace, String? tag)? _remoteLogger;

  /// Configure the logger.
  static void configure({
    LogLevel? minLevel,
    void Function(LogLevel, String, Object?, StackTrace?, String?)?
        remoteLogger,
  }) {
    if (minLevel != null) _minLevel = minLevel;
    if (remoteLogger != null) _remoteLogger = remoteLogger;
  }

  /// Get recent logs for crash reports.
  static List<String> getRecentLogs() {
    return _recentLogs.map((e) => e.toString()).toList();
  }

  /// Convenience getter for recent logs.
  static List<String> get recentLogs => getRecentLogs();

  /// Clear the log buffer.
  static void clearBuffer() {
    _recentLogs.clear();
  }

  /// Alias for clearBuffer.
  static void clearRecentLogs() => clearBuffer();

  /// Set a remote logger callback.
  static void setRemoteLogger(
    void Function(LogLevel level, String message, Object? error,
            StackTrace? stackTrace, String? tag)?
        logger,
  ) {
    _remoteLogger = logger;
  }

  /// Log a debug message (development only).
  static void debug(String message, {String? tag}) {
    _log(LogLevel.debug, message, tag: tag);
  }

  /// Log an informational message.
  static void info(String message, {String? tag}) {
    _log(LogLevel.info, message, tag: tag);
  }

  /// Log a warning.
  static void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    _log(LogLevel.warning, message,
        error: error, stackTrace: stackTrace, tag: tag);
  }

  /// Log an error.
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    _log(LogLevel.error, message,
        error: error, stackTrace: stackTrace, tag: tag);
  }

  /// Log an error from a specific location (file:line).
  static void errorAt(
    String location,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.error, message,
        error: error, stackTrace: stackTrace, tag: location);
  }

  static void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    if (level.priority < _minLevel.priority) return;

    final entry = _LogEntry(
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      tag: tag,
      timestamp: DateTime.now(),
    );

    // Add to buffer
    _recentLogs.add(entry);
    if (_recentLogs.length > _maxBufferSize) {
      _recentLogs.removeAt(0);
    }

    // Output to console
    _printLog(entry);

    // Send to remote logger if configured
    _remoteLogger?.call(level, message, error, stackTrace, tag);
  }

  static void _printLog(_LogEntry entry) {
    final buffer = StringBuffer();

    // Timestamp
    final time = entry.timestamp;
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

    // Format: [TIME] LEVEL [TAG] Message
    buffer.write('[$timeStr] ${entry.level.label}');
    if (entry.tag != null) {
      buffer.write(' [${entry.tag}]');
    }
    buffer.write(' ${entry.message}');

    // Error details
    if (entry.error != null) {
      buffer.write('\n  Error: ${entry.error}');
    }

    final logString = buffer.toString();

    // Use developer.log for better DevTools integration
    if (kDebugMode) {
      developer.log(
        logString,
        name: 'Tickety',
        level: _devLogLevel(entry.level),
        error: entry.error,
        stackTrace: entry.stackTrace,
      );
    } else {
      // In release, use debugPrint which is safer
      debugPrint(logString);
      if (entry.stackTrace != null && entry.level == LogLevel.error) {
        debugPrint(entry.stackTrace.toString());
      }
    }
  }

  static int _devLogLevel(LogLevel level) {
    return switch (level) {
      LogLevel.debug => 500,
      LogLevel.info => 800,
      LogLevel.warning => 900,
      LogLevel.error => 1000,
    };
  }
}

class _LogEntry {
  final LogLevel level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final String? tag;
  final DateTime timestamp;

  _LogEntry({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.tag,
    required this.timestamp,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('${timestamp.toIso8601String()} ${level.label}');
    if (tag != null) buffer.write(' [$tag]');
    buffer.write(' $message');
    if (error != null) buffer.write(' | Error: $error');
    return buffer.toString();
  }
}
