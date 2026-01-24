import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Provides access to environment configuration values.
///
/// Must call [initialize] before accessing any values.
abstract class EnvConfig {
  /// The Supabase project URL.
  static String get supabaseUrl {
    final url = dotenv.env['SUPABASE_URL'];
    if (url == null || url.isEmpty || url == 'your-supabase-url') {
      throw StateError(
        'SUPABASE_URL is not configured. '
        'Please update your .env file with your Supabase project URL.',
      );
    }
    return url;
  }

  /// The Supabase anonymous key for client-side access.
  static String get supabaseAnonKey {
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    if (key == null || key.isEmpty || key == 'your-supabase-anon-key') {
      throw StateError(
        'SUPABASE_ANON_KEY is not configured. '
        'Please update your .env file with your Supabase anon key.',
      );
    }
    return key;
  }

  /// Loads environment variables from the .env file.
  ///
  /// Call this once at app startup before accessing any env values.
  static Future<void> initialize() async {
    await dotenv.load(fileName: '.env');
  }
}
