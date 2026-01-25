/// Rate limiter to prevent brute-force attacks on authentication.
///
/// Tracks attempts within a sliding time window and blocks further
/// attempts when the maximum is exceeded.
class RateLimiter {
  /// Maximum number of attempts allowed within the window.
  final int maxAttempts;

  /// Time window for tracking attempts.
  final Duration window;

  final List<DateTime> _attempts = [];

  RateLimiter({
    this.maxAttempts = 5,
    this.window = const Duration(minutes: 15),
  });

  /// Cleans up old attempts that are outside the time window.
  void _cleanOldAttempts() {
    final cutoff = DateTime.now().subtract(window);
    _attempts.removeWhere((attempt) => attempt.isBefore(cutoff));
  }

  /// Checks if a new attempt is allowed.
  bool canAttempt() {
    _cleanOldAttempts();
    return _attempts.length < maxAttempts;
  }

  /// Records an attempt timestamp.
  void recordAttempt() {
    _attempts.add(DateTime.now());
  }

  /// Returns the duration until the rate limit resets, or null if not limited.
  Duration? timeUntilReset() {
    _cleanOldAttempts();
    if (_attempts.length < maxAttempts) {
      return null;
    }
    // The oldest attempt determines when the window expires
    final oldestAttempt = _attempts.first;
    final resetTime = oldestAttempt.add(window);
    final remaining = resetTime.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Returns remaining attempts before lockout.
  int get remainingAttempts {
    _cleanOldAttempts();
    return (maxAttempts - _attempts.length).clamp(0, maxAttempts);
  }

  /// Resets the rate limiter (e.g., after successful login).
  void reset() {
    _attempts.clear();
  }
}
