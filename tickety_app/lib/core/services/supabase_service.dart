import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/config.dart';

/// Singleton service providing access to the Supabase client.
///
/// Must call [initialize] before accessing [instance] or [client].
class SupabaseService {
  static SupabaseService? _instance;

  /// The singleton instance. Throws if [initialize] hasn't been called.
  static SupabaseService get instance {
    if (_instance == null) {
      throw StateError(
        'SupabaseService not initialized. Call SupabaseService.initialize() first.',
      );
    }
    return _instance!;
  }

  /// The Supabase client for database and auth operations.
  final SupabaseClient client;

  SupabaseService._(this.client);

  /// Initializes the Supabase client with environment configuration.
  ///
  /// Call this once at app startup after [EnvConfig.initialize].
  static Future<void> initialize() async {
    if (_instance != null) return;

    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
    );

    _instance = SupabaseService._(Supabase.instance.client);
  }

  /// Convenience getter for the current user's auth session.
  Session? get currentSession => client.auth.currentSession;

  /// Convenience getter for the current authenticated user.
  User? get currentUser => client.auth.currentUser;

  /// Whether there is a currently authenticated user.
  bool get isAuthenticated => currentUser != null;

  /// Stream of auth state changes.
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;
}
