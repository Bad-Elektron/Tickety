import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/errors.dart';
import '../services/services.dart';
import '../utils/utils.dart';

const _tag = 'AuthProvider';

/// Authentication state containing user info and loading status.
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final bool isRateLimited;
  final Duration? lockoutRemaining;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isRateLimited = false,
    this.lockoutRemaining,
  });

  bool get isAuthenticated => user != null;
  String? get email => user?.email;
  String? get displayName => user?.userMetadata?['display_name'] as String?;
  String? get userId => user?.id;

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    bool? isRateLimited,
    Duration? lockoutRemaining,
    bool clearUser = false,
    bool clearError = false,
    bool clearLockout = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isRateLimited: clearLockout ? false : (isRateLimited ?? this.isRateLimited),
      lockoutRemaining: clearLockout ? null : (lockoutRemaining ?? this.lockoutRemaining),
    );
  }
}

/// Notifier that manages authentication state and operations.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  StreamSubscription<AuthState>? _authSubscription;

  /// Rate limiter to prevent brute-force auth attempts.
  /// 5 attempts per 15 minutes.
  final _rateLimiter = RateLimiter(maxAttempts: 5, window: const Duration(minutes: 15));

  void _init() {
    AppLogger.debug('Initializing auth notifier', tag: _tag);

    // Set initial user if already logged in
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser != null) {
      AppLogger.info('Found existing session for: ${currentUser.email}', tag: _tag);
      state = state.copyWith(user: currentUser);
    }

    // Listen to auth state changes
    _authSubscription = SupabaseService.instance.client.auth.onAuthStateChange
        .map((event) => AuthState(user: event.session?.user))
        .listen((authState) {
      if (authState.user != null) {
        AppLogger.info('Auth state changed: signed in as ${authState.user?.email}', tag: _tag);
      } else {
        AppLogger.info('Auth state changed: signed out', tag: _tag);
      }
      state = state.copyWith(
        user: authState.user,
        clearUser: authState.user == null,
        clearError: true,
      );
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Sign up with email and password.
  Future<bool> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    // Check rate limit before attempting
    if (!_rateLimiter.canAttempt()) {
      final remaining = _rateLimiter.timeUntilReset();
      final minutes = remaining != null ? (remaining.inSeconds / 60).ceil() : 15;
      AppLogger.warning('Sign up rate limited for: $email', tag: _tag);
      state = state.copyWith(
        isRateLimited: true,
        lockoutRemaining: remaining,
        error: 'Too many attempts. Please try again in $minutes minute${minutes == 1 ? '' : 's'}.',
      );
      return false;
    }

    AppLogger.info('Attempting sign up for: $email', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true, clearLockout: true);
    _rateLimiter.recordAttempt();

    try {
      await SupabaseService.instance.client.auth.signUp(
        email: email,
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
      );
      AppLogger.info('Sign up successful for: $email', tag: _tag);
      _rateLimiter.reset(); // Clear rate limit on success
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Sign up failed for: $email',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
      return false;
    }
  }

  /// Sign in with email and password.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    // Check rate limit before attempting
    if (!_rateLimiter.canAttempt()) {
      final remaining = _rateLimiter.timeUntilReset();
      final minutes = remaining != null ? (remaining.inSeconds / 60).ceil() : 15;
      AppLogger.warning('Sign in rate limited for: $email', tag: _tag);
      state = state.copyWith(
        isRateLimited: true,
        lockoutRemaining: remaining,
        error: 'Too many attempts. Please try again in $minutes minute${minutes == 1 ? '' : 's'}.',
      );
      return false;
    }

    AppLogger.info('Attempting sign in for: $email', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true, clearLockout: true);
    _rateLimiter.recordAttempt();

    try {
      await SupabaseService.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      AppLogger.info('Sign in successful for: $email', tag: _tag);
      _rateLimiter.reset(); // Clear rate limit on success
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Sign in failed for: $email',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
      return false;
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    final email = state.email;
    AppLogger.info('Signing out user: $email', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await SupabaseService.instance.client.auth.signOut();
      AppLogger.info('Sign out successful', tag: _tag);
      state = state.copyWith(isLoading: false, clearUser: true);
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Sign out failed',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
    }
  }

  /// Send password reset email.
  Future<bool> resetPassword(String email) async {
    AppLogger.info('Requesting password reset for: $email', tag: _tag);
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await SupabaseService.instance.client.auth.resetPasswordForEmail(email);
      AppLogger.info('Password reset email sent to: $email', tag: _tag);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Password reset failed for: $email',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(isLoading: false, error: appError.userMessage);
      return false;
    }
  }

  /// Clear any error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// Global auth provider - use this throughout the app.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

/// Convenience provider for checking if user is authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

/// Convenience provider for getting current user ID.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).userId;
});
