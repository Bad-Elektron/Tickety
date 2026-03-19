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

  /// The Stripe publishable key for client-side payment processing.
  static String get stripePublishableKey {
    final key = dotenv.env['STRIPE_PUBLISHABLE_KEY'];
    if (key == null || key.isEmpty || key == 'pk_test_your_publishable_key_here') {
      throw StateError(
        'STRIPE_PUBLISHABLE_KEY is not configured. '
        'Please update your .env file with your Stripe publishable key.',
      );
    }
    return key;
  }

  /// The Google Places API key for location autocomplete.
  static String get googlePlacesApiKey {
    final key = dotenv.env['GOOGLE_PLACES_API_KEY'];
    if (key == null || key.isEmpty || key == 'YOUR_GOOGLE_PLACES_API_KEY') {
      throw StateError(
        'GOOGLE_PLACES_API_KEY is not configured. '
        'Please update your .env file with your Google Places API key.',
      );
    }
    return key;
  }

  /// The Blockfrost project ID for Cardano API access.
  static String get blockfrostProjectId {
    final key = dotenv.env['BLOCKFROST_PROJECT_ID'];
    if (key == null || key.isEmpty) {
      throw StateError(
        'BLOCKFROST_PROJECT_ID is not configured. '
        'Please update your .env file with your Blockfrost project ID.',
      );
    }
    return key;
  }

  /// The shared secret for verifying NFC ticket signatures (Layer 0).
  ///
  /// Must match `TICKET_SIGNING_SECRET` set in Supabase edge function secrets.
  static String get ticketSigningSecret {
    final key = dotenv.env['TICKET_SIGNING_SECRET'];
    if (key == null || key.isEmpty) {
      throw StateError(
        'TICKET_SIGNING_SECRET is not configured. '
        'Please update your .env file with the ticket signing secret.',
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
