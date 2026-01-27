/// Base class for all app-specific exceptions.
///
/// All custom exceptions extend this class, making it easy to:
/// - Catch all app errors with a single catch block
/// - Distinguish app errors from system errors
/// - Get user-friendly messages
sealed class AppException implements Exception {
  /// User-friendly message to display.
  final String message;

  /// Technical details for logging (not shown to users).
  final String? technicalDetails;

  /// The original error that caused this exception.
  final Object? cause;

  const AppException(
    this.message, {
    this.technicalDetails,
    this.cause,
  });

  @override
  String toString() => 'AppException: $message';

  /// Get a user-friendly error message.
  String get userMessage => message;
}

/// Network-related errors (no connection, timeout, etc.).
class NetworkException extends AppException {
  const NetworkException(
    super.message, {
    super.technicalDetails,
    super.cause,
  });

  factory NetworkException.noConnection() => const NetworkException(
        'No internet connection. Please check your network and try again.',
        technicalDetails: 'Network unreachable',
      );

  factory NetworkException.timeout() => const NetworkException(
        'Request timed out. Please try again.',
        technicalDetails: 'Connection timeout',
      );

  factory NetworkException.serverError([String? details]) => NetworkException(
        'Server error. Please try again later.',
        technicalDetails: details ?? 'HTTP 5xx error',
      );
}

/// Authentication errors (invalid credentials, session expired, etc.).
class AuthException extends AppException {
  const AuthException(
    super.message, {
    super.technicalDetails,
    super.cause,
  });

  factory AuthException.invalidCredentials() => const AuthException(
        'Invalid email or password.',
        technicalDetails: 'Authentication failed',
      );

  factory AuthException.sessionExpired() => const AuthException(
        'Your session has expired. Please sign in again.',
        technicalDetails: 'Token expired',
      );

  factory AuthException.notAuthenticated() => const AuthException(
        'Please sign in to continue.',
        technicalDetails: 'No active session',
      );

  factory AuthException.emailNotConfirmed() => const AuthException(
        'Please verify your email address before signing in.',
        technicalDetails: 'Email not confirmed',
      );

  factory AuthException.accountDisabled() => const AuthException(
        'This account has been disabled.',
        technicalDetails: 'Account disabled',
      );

  factory AuthException.fromMessage(String message) {
    // Map common Supabase auth error messages to user-friendly ones
    final lowerMessage = message.toLowerCase();

    if (lowerMessage.contains('invalid login credentials') ||
        lowerMessage.contains('invalid password')) {
      return AuthException.invalidCredentials();
    }
    if (lowerMessage.contains('email not confirmed')) {
      return AuthException.emailNotConfirmed();
    }
    if (lowerMessage.contains('token') && lowerMessage.contains('expired')) {
      return AuthException.sessionExpired();
    }
    if (lowerMessage.contains('user not found')) {
      return const AuthException('No account found with this email.');
    }
    if (lowerMessage.contains('email already registered') ||
        lowerMessage.contains('already exists')) {
      return const AuthException(
        'An account with this email already exists.',
      );
    }

    // Default: return original message
    return AuthException(message);
  }
}

/// Validation errors (invalid input, missing required fields, etc.).
class ValidationException extends AppException {
  /// The field that failed validation (if applicable).
  final String? field;

  const ValidationException(
    super.message, {
    this.field,
    super.technicalDetails,
    super.cause,
  });

  factory ValidationException.required(String fieldName) => ValidationException(
        '$fieldName is required.',
        field: fieldName,
        technicalDetails: 'Missing required field: $fieldName',
      );

  factory ValidationException.invalid(String fieldName, [String? reason]) =>
      ValidationException(
        reason ?? 'Invalid $fieldName.',
        field: fieldName,
        technicalDetails: 'Invalid field: $fieldName',
      );

  factory ValidationException.tooLong(String fieldName, int maxLength) =>
      ValidationException(
        '$fieldName must be $maxLength characters or less.',
        field: fieldName,
        technicalDetails: 'Field too long: $fieldName (max: $maxLength)',
      );
}

/// Data errors (not found, already exists, constraint violations).
class DataException extends AppException {
  const DataException(
    super.message, {
    super.technicalDetails,
    super.cause,
  });

  factory DataException.notFound(String entityType) => DataException(
        '$entityType not found.',
        technicalDetails: '$entityType lookup returned null',
      );

  factory DataException.alreadyExists(String entityType) => DataException(
        '$entityType already exists.',
        technicalDetails: 'Duplicate $entityType',
      );

  factory DataException.constraintViolation([String? details]) => DataException(
        'This operation is not allowed.',
        technicalDetails: details ?? 'Database constraint violation',
      );

  factory DataException.stale() => const DataException(
        'This data has changed. Please refresh and try again.',
        technicalDetails: 'Stale data / optimistic lock failure',
      );
}

/// Permission errors (not authorized, insufficient permissions).
class PermissionException extends AppException {
  const PermissionException(
    super.message, {
    super.technicalDetails,
    super.cause,
  });

  factory PermissionException.denied([String? action]) => PermissionException(
        action != null
            ? 'You do not have permission to $action.'
            : 'You do not have permission to perform this action.',
        technicalDetails: 'Permission denied: $action',
      );

  factory PermissionException.notOwner() => const PermissionException(
        'You can only modify your own content.',
        technicalDetails: 'Not owner of resource',
      );
}

/// Business logic errors (invalid state, operation not allowed).
class BusinessException extends AppException {
  const BusinessException(
    super.message, {
    super.technicalDetails,
    super.cause,
  });

  factory BusinessException.ticketAlreadyUsed() => const BusinessException(
        'This ticket has already been checked in.',
        technicalDetails: 'Ticket status: used',
      );

  factory BusinessException.ticketCancelled() => const BusinessException(
        'This ticket has been cancelled.',
        technicalDetails: 'Ticket status: cancelled',
      );

  factory BusinessException.eventEnded() => const BusinessException(
        'This event has already ended.',
        technicalDetails: 'Event date in past',
      );

  factory BusinessException.soldOut() => const BusinessException(
        'This event is sold out.',
        technicalDetails: 'No tickets available',
      );

  factory BusinessException.custom(String message) => BusinessException(
        message,
        technicalDetails: 'Business rule violation',
      );
}

/// Unknown/unexpected errors.
class UnknownException extends AppException {
  const UnknownException(
    super.message, {
    super.technicalDetails,
    super.cause,
  });

  factory UnknownException.fromError(Object error, [StackTrace? stackTrace]) {
    return UnknownException(
      'Something went wrong. Please try again.',
      technicalDetails: error.toString(),
      cause: error,
    );
  }
}

/// Payment-related errors (payment failed, card declined, etc.).
class PaymentException extends AppException {
  /// The Stripe error code, if available.
  final String? stripeErrorCode;

  /// The decline code from the card issuer, if applicable.
  final String? declineCode;

  const PaymentException(
    super.message, {
    this.stripeErrorCode,
    this.declineCode,
    super.technicalDetails,
    super.cause,
  });

  factory PaymentException.cancelled() => const PaymentException(
        'Payment was cancelled.',
        technicalDetails: 'User cancelled payment',
      );

  factory PaymentException.cardDeclined([String? declineCode]) {
    String message;
    switch (declineCode) {
      case 'insufficient_funds':
        message = 'Your card has insufficient funds.';
        break;
      case 'lost_card':
      case 'stolen_card':
        message = 'Your card has been reported lost or stolen.';
        break;
      case 'expired_card':
        message = 'Your card has expired.';
        break;
      case 'incorrect_cvc':
        message = 'The security code is incorrect.';
        break;
      case 'processing_error':
        message = 'An error occurred while processing your card. Please try again.';
        break;
      case 'incorrect_number':
        message = 'The card number is incorrect.';
        break;
      default:
        message = 'Your card was declined. Please try a different payment method.';
    }
    return PaymentException(
      message,
      declineCode: declineCode,
      technicalDetails: 'Card declined: $declineCode',
    );
  }

  factory PaymentException.networkError() => const PaymentException(
        'Unable to process payment. Please check your connection and try again.',
        technicalDetails: 'Network error during payment',
      );

  factory PaymentException.invalidCard() => const PaymentException(
        'The card information is invalid. Please check and try again.',
        technicalDetails: 'Invalid card data',
      );

  factory PaymentException.authenticationRequired() => const PaymentException(
        'Additional authentication is required. Please complete verification.',
        technicalDetails: '3D Secure authentication required',
      );

  factory PaymentException.serverError() => const PaymentException(
        'Payment service is temporarily unavailable. Please try again later.',
        technicalDetails: 'Payment server error',
      );

  factory PaymentException.fromStripeError(dynamic stripeException) {
    // Handle StripeException from flutter_stripe package
    final error = stripeException.error;
    final code = error.code?.toString() ?? '';
    final message = error.message ?? 'Payment failed';
    final localizedMessage = error.localizedMessage;

    // Map common Stripe error codes
    if (code.contains('Canceled') || code == 'Canceled') {
      return PaymentException.cancelled();
    }

    if (message.toLowerCase().contains('declined') ||
        code == 'card_declined') {
      final declineCode = error.declineCode;
      return PaymentException.cardDeclined(declineCode);
    }

    if (message.toLowerCase().contains('network') ||
        message.toLowerCase().contains('connection')) {
      return PaymentException.networkError();
    }

    if (code == 'authentication_required' ||
        message.toLowerCase().contains('authentication')) {
      return PaymentException.authenticationRequired();
    }

    if (code == 'invalid_card' ||
        message.toLowerCase().contains('invalid')) {
      return PaymentException.invalidCard();
    }

    // Default: use the localized message or a generic error
    return PaymentException(
      localizedMessage ?? message,
      stripeErrorCode: code,
      technicalDetails: 'Stripe error: $code - $message',
      cause: stripeException,
    );
  }

  factory PaymentException.refundFailed([String? reason]) => PaymentException(
        reason ?? 'Refund failed. Please try again or contact support.',
        technicalDetails: 'Refund processing failed: $reason',
      );

  factory PaymentException.alreadyRefunded() => const PaymentException(
        'This payment has already been refunded.',
        technicalDetails: 'Duplicate refund attempt',
      );

  factory PaymentException.connectAccountRequired() => const PaymentException(
        'Please complete your payout setup before listing tickets for sale.',
        technicalDetails: 'Stripe Connect account not onboarded',
      );

  factory PaymentException.platformNotSupported() => const PaymentException(
        'Payments are only available on mobile devices (iOS and Android).',
        technicalDetails: 'Stripe Payment Sheet not supported on this platform',
      );
}

/// Subscription-related errors (upgrade failed, cancellation failed, etc.).
class SubscriptionException extends AppException {
  const SubscriptionException(
    super.message, {
    super.technicalDetails,
    super.cause,
  });

  factory SubscriptionException.alreadySubscribed() => const SubscriptionException(
        'You already have an active subscription.',
        technicalDetails: 'User already has active subscription',
      );

  factory SubscriptionException.notSubscribed() => const SubscriptionException(
        'You do not have an active subscription.',
        technicalDetails: 'No active subscription found',
      );

  factory SubscriptionException.upgradeFailed([String? reason]) => SubscriptionException(
        reason ?? 'Failed to upgrade your subscription. Please try again.',
        technicalDetails: 'Subscription upgrade failed: $reason',
      );

  factory SubscriptionException.cancelFailed([String? reason]) => SubscriptionException(
        reason ?? 'Failed to cancel your subscription. Please try again.',
        technicalDetails: 'Subscription cancellation failed: $reason',
      );

  factory SubscriptionException.resumeFailed([String? reason]) => SubscriptionException(
        reason ?? 'Failed to resume your subscription. Please try again.',
        technicalDetails: 'Subscription resume failed: $reason',
      );
}
