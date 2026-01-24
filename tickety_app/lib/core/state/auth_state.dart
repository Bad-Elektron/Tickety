import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/services.dart';

/// Global authentication state manager.
///
/// Uses ChangeNotifier for reactive updates across the app.
/// Listens to Supabase auth state changes automatically.
class AuthState extends ChangeNotifier {
  static final AuthState _instance = AuthState._internal();

  factory AuthState() => _instance;

  AuthState._internal() {
    _init();
  }

  StreamSubscription<AuthState>? _authSubscription;
  User? _user;
  bool _isLoading = false;
  String? _error;

  /// The currently authenticated user, or null if not logged in.
  User? get user => _user;

  /// Whether the user is currently authenticated.
  bool get isAuthenticated => _user != null;

  /// Whether an auth operation is in progress.
  bool get isLoading => _isLoading;

  /// The last authentication error, if any.
  String? get error => _error;

  /// The user's display name from metadata or email prefix.
  String? get displayName {
    if (_user == null) return null;
    final metadata = _user!.userMetadata;
    if (metadata != null && metadata['display_name'] != null) {
      return metadata['display_name'] as String;
    }
    return _user!.email?.split('@').first;
  }

  /// The user's email address.
  String? get email => _user?.email;

  void _init() {
    // Get initial user state
    _user = SupabaseService.instance.currentUser;

    // Listen for auth state changes
    SupabaseService.instance.authStateChanges.listen((data) {
      final event = data.event;
      final session = data.session;

      switch (event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          _user = session?.user;
          _error = null;
          notifyListeners();
        case AuthChangeEvent.signedOut:
          _user = null;
          _error = null;
          notifyListeners();
        case AuthChangeEvent.passwordRecovery:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.mfaChallengeVerified:
          // No action needed for these events
          break;
        default:
          // Handle any future auth events by clearing user if session is null
          if (session == null) {
            _user = null;
            notifyListeners();
          }
      }
    });
  }

  /// Signs up a new user with email and password.
  ///
  /// [displayName] is stored in user metadata and used for the profile.
  Future<bool> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      final response = await SupabaseService.instance.client.auth.signUp(
        email: email,
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
      );

      if (response.user != null) {
        _user = response.user;
        notifyListeners();
        return true;
      }

      _error = 'Sign up failed. Please try again.';
      notifyListeners();
      return false;
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred.';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Signs in an existing user with email and password.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      final response =
          await SupabaseService.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        _user = response.user;
        notifyListeners();
        return true;
      }

      _error = 'Sign in failed. Please check your credentials.';
      notifyListeners();
      return false;
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred.';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Signs out the current user.
  Future<void> signOut() async {
    _setLoading(true);
    _error = null;

    try {
      await SupabaseService.instance.client.auth.signOut();
      _user = null;
      notifyListeners();
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to sign out.';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Sends a password reset email.
  Future<bool> resetPassword(String email) async {
    _setLoading(true);
    _error = null;

    try {
      await SupabaseService.instance.client.auth.resetPasswordForEmail(email);
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to send reset email.';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Clears any error message.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
