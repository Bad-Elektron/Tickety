import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'app_exception.dart';
import 'app_logger.dart';

/// Centralized error handling utilities.
class ErrorHandler {
  ErrorHandler._();

  /// Initialize global error handlers.
  ///
  /// Call this in main() before runApp().
  static void init() {
    // Handle Flutter framework errors
    FlutterError.onError = (details) {
      AppLogger.error(
        'Flutter error: ${details.summary}',
        error: details.exception,
        stackTrace: details.stack,
        tag: 'Flutter',
      );

      // In debug mode, also use default handler for red screen
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    // Handle errors outside of Flutter (async errors, isolates, etc.)
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.error(
        'Platform error',
        error: error,
        stackTrace: stack,
        tag: 'Platform',
      );
      return true; // Prevents app crash
    };
  }

  /// Run a zone with error handling.
  ///
  /// Wraps the app in an error zone to catch uncaught async errors.
  static R runGuarded<R>(R Function() body) {
    return runZonedGuarded(body, (error, stack) {
      AppLogger.error(
        'Uncaught async error',
        error: error,
        stackTrace: stack,
        tag: 'Zone',
      );
    }) as R;
  }

  /// Convert any error to an AppException.
  ///
  /// This normalizes errors from various sources (Supabase, network, etc.)
  /// into our typed exception hierarchy.
  static AppException normalize(Object error, [StackTrace? stackTrace]) {
    // Already an AppException - return as-is
    if (error is AppException) {
      return error;
    }

    // Supabase Auth errors
    if (error is supabase.AuthException) {
      return AuthException.fromMessage(error.message);
    }

    // Supabase Postgres errors
    if (error is supabase.PostgrestException) {
      return _handlePostgrestError(error);
    }

    // Supabase Edge Function errors
    if (error is supabase.FunctionException) {
      final details = error.details;
      String? message;
      if (details is Map) {
        message = details['error']?.toString();
      } else if (details is String && details.isNotEmpty) {
        message = details;
      }
      return BusinessException(
        message ?? 'Service temporarily unavailable. Please try again.',
        technicalDetails: 'Edge function error (${error.status}): ${error.reasonPhrase ?? message}',
        cause: error,
      );
    }

    // Stripe errors
    if (error is stripe.StripeException) {
      return PaymentException.fromStripeError(error);
    }

    // Network errors
    if (error is SocketException) {
      return NetworkException.noConnection();
    }
    if (error is TimeoutException) {
      return NetworkException.timeout();
    }
    if (error is HttpException) {
      return NetworkException.serverError(error.message);
    }

    // Format/parse errors (usually validation issues)
    if (error is FormatException) {
      return ValidationException(
        'Invalid data format.',
        technicalDetails: error.message,
        cause: error,
      );
    }

    // State errors
    if (error is StateError) {
      return BusinessException(
        error.message,
        technicalDetails: 'StateError',
        cause: error,
      );
    }

    // Unknown error
    return UnknownException.fromError(error, stackTrace);
  }

  /// Handle Supabase Postgrest errors.
  static AppException _handlePostgrestError(supabase.PostgrestException error) {
    final code = error.code;
    final message = error.message.toLowerCase();

    // Row Level Security violations
    if (code == '42501' || message.contains('permission denied')) {
      return PermissionException.denied();
    }

    // Not found
    if (code == 'PGRST116' || message.contains('no rows')) {
      return const DataException('Record not found.');
    }

    // Unique constraint violation
    if (code == '23505' || message.contains('duplicate') || message.contains('unique')) {
      return const DataException('This record already exists.');
    }

    // Foreign key violation
    if (code == '23503' || message.contains('foreign key')) {
      return DataException.constraintViolation('Referenced record does not exist.');
    }

    // Check constraint violation
    if (code == '23514') {
      return DataException.constraintViolation('Invalid data.');
    }

    // Not null violation
    if (code == '23502') {
      return const ValidationException('A required field is missing.');
    }

    // Default database error
    return DataException(
      'Database error. Please try again.',
      technicalDetails: '${error.code}: ${error.message}',
      cause: error,
    );
  }

  /// Execute a function and handle errors consistently.
  ///
  /// Returns null on error (for operations where failure is acceptable).
  /// Logs the error with context.
  static Future<T?> tryAsync<T>(
    Future<T> Function() fn, {
    required String operation,
    String? tag,
    T? fallback,
  }) async {
    try {
      return await fn();
    } catch (e, s) {
      final normalized = normalize(e, s);
      AppLogger.error(
        'Failed: $operation',
        error: normalized.technicalDetails ?? e,
        stackTrace: s,
        tag: tag,
      );
      return fallback;
    }
  }

  /// Execute a function and rethrow as AppException.
  ///
  /// Use this when you need to propagate errors up the call stack.
  static Future<T> wrapAsync<T>(
    Future<T> Function() fn, {
    required String operation,
    String? tag,
  }) async {
    try {
      return await fn();
    } catch (e, s) {
      final normalized = normalize(e, s);
      AppLogger.error(
        'Failed: $operation',
        error: normalized.technicalDetails ?? e,
        stackTrace: s,
        tag: tag,
      );
      throw normalized;
    }
  }
}

/// Extension for cleaner error handling in providers.
extension FutureErrorHandling<T> on Future<T> {
  /// Handle errors and return null on failure.
  Future<T?> tryOrNull({
    required String operation,
    String? tag,
  }) async {
    try {
      return await this;
    } catch (e, s) {
      final normalized = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed: $operation',
        error: normalized.technicalDetails ?? e,
        stackTrace: s,
        tag: tag,
      );
      return null;
    }
  }

  /// Handle errors and return a fallback value.
  Future<T> tryOr(
    T fallback, {
    required String operation,
    String? tag,
  }) async {
    try {
      return await this;
    } catch (e, s) {
      final normalized = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed: $operation',
        error: normalized.technicalDetails ?? e,
        stackTrace: s,
        tag: tag,
      );
      return fallback;
    }
  }
}
