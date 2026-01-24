import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/services.dart';

/// Authentication state containing user info and loading status.
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
  });

  bool get isAuthenticated => user != null;
  String? get email => user?.email;
  String? get displayName => user?.userMetadata?['display_name'] as String?;
  String? get userId => user?.id;

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier that manages authentication state and operations.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  StreamSubscription<AuthState>? _authSubscription;

  void _init() {
    // Set initial user if already logged in
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser != null) {
      state = state.copyWith(user: currentUser);
    }

    // Listen to auth state changes
    _authSubscription = SupabaseService.instance.client.auth.onAuthStateChange
        .map((event) => AuthState(user: event.session?.user))
        .listen((authState) {
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
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await SupabaseService.instance.client.auth.signUp(
        email: email,
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
      );
      state = state.copyWith(isLoading: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Sign in with email and password.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await SupabaseService.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      state = state.copyWith(isLoading: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await SupabaseService.instance.client.auth.signOut();
      state = state.copyWith(isLoading: false, clearUser: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Send password reset email.
  Future<bool> resetPassword(String email) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await SupabaseService.instance.client.auth.resetPasswordForEmail(email);
      state = state.copyWith(isLoading: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
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
