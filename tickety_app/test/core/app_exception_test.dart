import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/core/errors/app_exception.dart';

void main() {
  group('NetworkException', () {
    test('noConnection has correct message', () {
      final exception = NetworkException.noConnection();

      expect(exception.message, contains('internet connection'));
      expect(exception.userMessage, contains('internet connection'));
      expect(exception.technicalDetails, isNotNull);
    });

    test('timeout has correct message', () {
      final exception = NetworkException.timeout();

      expect(exception.message, contains('timed out'));
      expect(exception.technicalDetails, contains('timeout'));
    });

    test('serverError has correct message', () {
      final exception = NetworkException.serverError('500 Internal');

      expect(exception.message, contains('Server error'));
      expect(exception.technicalDetails, contains('500 Internal'));
    });

    test('serverError uses default details when none provided', () {
      final exception = NetworkException.serverError();

      expect(exception.technicalDetails, contains('5xx'));
    });
  });

  group('AuthException', () {
    test('invalidCredentials has correct message', () {
      final exception = AuthException.invalidCredentials();

      expect(exception.message, contains('Invalid'));
      expect(exception.message.toLowerCase(), contains('email'));
    });

    test('sessionExpired has correct message', () {
      final exception = AuthException.sessionExpired();

      expect(exception.message, contains('expired'));
      expect(exception.message, contains('sign in'));
    });

    test('notAuthenticated has correct message', () {
      final exception = AuthException.notAuthenticated();

      expect(exception.message, contains('sign in'));
    });

    test('emailNotConfirmed has correct message', () {
      final exception = AuthException.emailNotConfirmed();

      expect(exception.message, contains('verify'));
      expect(exception.message, contains('email'));
    });

    test('accountDisabled has correct message', () {
      final exception = AuthException.accountDisabled();

      expect(exception.message, contains('disabled'));
    });

    test('fromMessage maps invalid credentials', () {
      final exception = AuthException.fromMessage('Invalid login credentials');

      expect(exception.message, contains('Invalid'));
    });

    test('fromMessage maps email not confirmed', () {
      final exception = AuthException.fromMessage('Email not confirmed');

      expect(exception.message, contains('verify'));
    });

    test('fromMessage maps token expired', () {
      final exception = AuthException.fromMessage('Token has expired');

      expect(exception.message, contains('expired'));
    });

    test('fromMessage maps user not found', () {
      final exception = AuthException.fromMessage('User not found');

      expect(exception.message, contains('No account'));
    });

    test('fromMessage maps email already registered', () {
      final exception = AuthException.fromMessage('Email already registered');

      expect(exception.message, contains('already exists'));
    });

    test('fromMessage returns original for unknown messages', () {
      final exception = AuthException.fromMessage('Custom auth error');

      expect(exception.message, 'Custom auth error');
    });
  });

  group('ValidationException', () {
    test('required has correct message', () {
      final exception = ValidationException.required('Email');

      expect(exception.message, contains('Email'));
      expect(exception.message, contains('required'));
      expect(exception.field, 'Email');
    });

    test('invalid has correct message', () {
      final exception = ValidationException.invalid('Phone', 'Must be 10 digits');

      expect(exception.message, 'Must be 10 digits');
      expect(exception.field, 'Phone');
    });

    test('invalid uses default message when reason not provided', () {
      final exception = ValidationException.invalid('Phone');

      expect(exception.message, contains('Invalid'));
      expect(exception.message, contains('Phone'));
    });

    test('tooLong has correct message', () {
      final exception = ValidationException.tooLong('Name', 50);

      expect(exception.message, contains('Name'));
      expect(exception.message, contains('50'));
      expect(exception.field, 'Name');
    });
  });

  group('DataException', () {
    test('notFound has correct message', () {
      final exception = DataException.notFound('Event');

      expect(exception.message, contains('Event'));
      expect(exception.message, contains('not found'));
    });

    test('alreadyExists has correct message', () {
      final exception = DataException.alreadyExists('User');

      expect(exception.message, contains('User'));
      expect(exception.message, contains('already exists'));
    });

    test('constraintViolation has correct message', () {
      final exception = DataException.constraintViolation('Cannot delete');

      expect(exception.message, contains('not allowed'));
      expect(exception.technicalDetails, contains('Cannot delete'));
    });

    test('constraintViolation uses default when no details', () {
      final exception = DataException.constraintViolation();

      expect(exception.technicalDetails, contains('constraint'));
    });

    test('stale has correct message', () {
      final exception = DataException.stale();

      expect(exception.message, contains('changed'));
      expect(exception.message, contains('refresh'));
    });
  });

  group('PermissionException', () {
    test('denied has correct message with action', () {
      final exception = PermissionException.denied('delete this event');

      expect(exception.message, contains('permission'));
      expect(exception.message, contains('delete this event'));
    });

    test('denied has generic message without action', () {
      final exception = PermissionException.denied();

      expect(exception.message, contains('permission'));
      expect(exception.message, contains('perform this action'));
    });

    test('notOwner has correct message', () {
      final exception = PermissionException.notOwner();

      expect(exception.message, contains('own'));
    });
  });

  group('BusinessException', () {
    test('ticketAlreadyUsed has correct message', () {
      final exception = BusinessException.ticketAlreadyUsed();

      expect(exception.message, contains('already'));
      expect(exception.message, contains('checked in'));
    });

    test('ticketCancelled has correct message', () {
      final exception = BusinessException.ticketCancelled();

      expect(exception.message, contains('cancelled'));
    });

    test('eventEnded has correct message', () {
      final exception = BusinessException.eventEnded();

      expect(exception.message, contains('ended'));
    });

    test('soldOut has correct message', () {
      final exception = BusinessException.soldOut();

      expect(exception.message, contains('sold out'));
    });

    test('custom creates exception with custom message', () {
      final exception = BusinessException.custom('Custom business rule');

      expect(exception.message, 'Custom business rule');
    });
  });

  group('UnknownException', () {
    test('fromError wraps error correctly', () {
      final originalError = Exception('Something bad happened');
      final exception = UnknownException.fromError(originalError);

      expect(exception.message, contains('Something went wrong'));
      expect(exception.technicalDetails, contains('Something bad happened'));
      expect(exception.cause, originalError);
    });

    test('provides user-friendly message regardless of original error', () {
      final exception = UnknownException.fromError('raw string error');

      expect(exception.userMessage, contains('try again'));
    });
  });

  group('AppException base class', () {
    test('toString includes message', () {
      const exception = NetworkException('Test message');

      expect(exception.toString(), contains('Test message'));
    });

    test('userMessage returns message', () {
      const exception = DataException('User visible message');

      expect(exception.userMessage, 'User visible message');
    });
  });
}
