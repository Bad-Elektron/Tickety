/// Input validation utilities for security and data integrity.
abstract class Validators {
  /// Maximum lengths for text fields
  static const int maxTitleLength = 200;
  static const int maxSubtitleLength = 500;
  static const int maxDescriptionLength = 5000;
  static const int maxDisplayNameLength = 100;
  static const int maxEmailLength = 254;

  /// Validates an email address format.
  static String? email(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    if (value.length > maxEmailLength) {
      return 'Email is too long';
    }
    // Basic email regex - Supabase does full validation
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email';
    }
    return null;
  }

  /// Validates a password meets complexity requirements.
  /// Requires: 8+ chars, uppercase, lowercase, and a number.
  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (value.length > 128) {
      return 'Password is too long';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Must contain an uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Must contain a lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Must contain a number';
    }
    return null;
  }

  /// Validates a Cardano wallet address (Bech32 format).
  /// Accepts mainnet (addr1...) and testnet (addr_test1...) addresses.
  static String? walletAddress(String? value) {
    if (value == null || value.isEmpty) {
      return 'Wallet address is required';
    }
    // Cardano Shelley addresses use Bech32 encoding
    // Mainnet: starts with "addr1", Testnet: starts with "addr_test1"
    // Bech32 charset: lowercase a-z (except b, i, o) and 0-9
    final cardanoRegex = RegExp(
      r'^(addr1[ac-hj-np-z02-9]{53,}|addr_test1[ac-hj-np-z02-9]{50,})$',
    );
    if (!cardanoRegex.hasMatch(value)) {
      return 'Invalid Cardano wallet address';
    }
    return null;
  }

  /// Validates event title.
  static String? eventTitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Title is required';
    }
    if (value.length > maxTitleLength) {
      return 'Title must be under $maxTitleLength characters';
    }
    return null;
  }

  /// Validates event subtitle.
  static String? eventSubtitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Subtitle is required';
    }
    if (value.length > maxSubtitleLength) {
      return 'Subtitle must be under $maxSubtitleLength characters';
    }
    return null;
  }

  /// Validates optional description.
  static String? description(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length > maxDescriptionLength) {
      return 'Description must be under $maxDescriptionLength characters';
    }
    return null;
  }

  /// Validates display name.
  static String? displayName(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length > maxDisplayNameLength) {
      return 'Name must be under $maxDisplayNameLength characters';
    }
    // Prevent potentially malicious characters
    if (RegExp(r'[<>\"\\]').hasMatch(value)) {
      return 'Name contains invalid characters';
    }
    return null;
  }

  /// Validates a URL is safe (https preferred).
  static String? url(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return 'Please enter a valid URL';
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return 'URL must start with http:// or https://';
    }
    return null;
  }

  /// Sanitizes text input by trimming and removing control characters.
  static String sanitize(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '') // Remove control chars
        .replaceAll(RegExp(r'\s+'), ' '); // Normalize whitespace
  }
}
