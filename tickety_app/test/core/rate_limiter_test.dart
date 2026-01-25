import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/core/utils/rate_limiter.dart';

void main() {
  group('RateLimiter', () {
    test('allows attempts under the limit', () {
      final limiter = RateLimiter(maxAttempts: 3);

      expect(limiter.canAttempt(), isTrue);
      limiter.recordAttempt();

      expect(limiter.canAttempt(), isTrue);
      limiter.recordAttempt();

      expect(limiter.canAttempt(), isTrue);
      limiter.recordAttempt();

      // Now at limit
      expect(limiter.canAttempt(), isFalse);
    });

    test('tracks remaining attempts correctly', () {
      final limiter = RateLimiter(maxAttempts: 5);

      expect(limiter.remainingAttempts, 5);
      limiter.recordAttempt();
      expect(limiter.remainingAttempts, 4);
      limiter.recordAttempt();
      expect(limiter.remainingAttempts, 3);
    });

    test('reset clears all attempts', () {
      final limiter = RateLimiter(maxAttempts: 2);

      limiter.recordAttempt();
      limiter.recordAttempt();
      expect(limiter.canAttempt(), isFalse);

      limiter.reset();
      expect(limiter.canAttempt(), isTrue);
      expect(limiter.remainingAttempts, 2);
    });

    test('timeUntilReset returns null when not limited', () {
      final limiter = RateLimiter(maxAttempts: 5);

      expect(limiter.timeUntilReset(), isNull);

      limiter.recordAttempt();
      expect(limiter.timeUntilReset(), isNull);
    });

    test('timeUntilReset returns duration when limited', () {
      final limiter = RateLimiter(
        maxAttempts: 1,
        window: const Duration(minutes: 15),
      );

      limiter.recordAttempt();
      final remaining = limiter.timeUntilReset();

      expect(remaining, isNotNull);
      // Should be close to 15 minutes (allowing for test execution time)
      expect(remaining!.inMinutes, greaterThanOrEqualTo(14));
      expect(remaining.inMinutes, lessThanOrEqualTo(15));
    });

    test('default values are 5 attempts per 15 minutes', () {
      final limiter = RateLimiter();

      // Can make 5 attempts
      for (var i = 0; i < 5; i++) {
        expect(limiter.canAttempt(), isTrue);
        limiter.recordAttempt();
      }

      expect(limiter.canAttempt(), isFalse);
    });

    test('custom maxAttempts works', () {
      final limiter = RateLimiter(maxAttempts: 2);

      limiter.recordAttempt();
      limiter.recordAttempt();
      expect(limiter.canAttempt(), isFalse);
    });

    test('remainingAttempts never goes negative', () {
      final limiter = RateLimiter(maxAttempts: 2);

      limiter.recordAttempt();
      limiter.recordAttempt();
      limiter.recordAttempt(); // Extra attempt
      limiter.recordAttempt(); // Extra attempt

      expect(limiter.remainingAttempts, 0);
    });
  });
}
