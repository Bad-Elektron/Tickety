import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CSV-based localization service modeled on the GDF Localization architecture.
///
/// Loads a single CSV asset containing all localization keys and their
/// translations across all supported languages. Supports variable injection
/// via `{0}`, `{1}` placeholders and runtime language switching.
class LocalizationService {
  /// locale code → (key → translated text)
  final Map<String, Map<String, String>> _data = {};

  /// Ordered list of supported locale codes parsed from CSV header.
  final List<String> _supportedLocales = [];

  String _currentLocale = 'en';

  static const _prefsKey = 'preferred_locale';
  static const _assetPath = 'assets/localization.csv';

  String get currentLocale => _currentLocale;

  List<String> get supportedLocales => List.unmodifiable(_supportedLocales);

  /// Load and parse the CSV from app assets, then restore saved locale.
  Future<void> loadFromAsset() async {
    final csvString = await rootBundle.loadString(_assetPath);
    _parseCsv(csvString);

    // Restore saved locale preference
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && _data.containsKey(saved)) {
      _currentLocale = saved;
    } else {
      _currentLocale = 'en';
    }
  }

  /// Parse CSV with proper quote handling (matches GDF ParseCsv algorithm).
  void _parseCsv(String csv) {
    _data.clear();
    _supportedLocales.clear();

    final rows = <List<String>>[];
    var currentField = StringBuffer();
    var currentRow = <String>[];
    var inQuotes = false;

    for (var i = 0; i < csv.length; i++) {
      final c = csv[i];

      if (inQuotes) {
        if (c == '"') {
          // Check for escaped quote ""
          if (i + 1 < csv.length && csv[i + 1] == '"') {
            currentField.write('"');
            i++; // skip next quote
          } else {
            inQuotes = false;
          }
        } else {
          currentField.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          currentRow.add(currentField.toString());
          currentField = StringBuffer();
        } else if (c == '\n') {
          currentRow.add(currentField.toString());
          currentField = StringBuffer();
          if (currentRow.isNotEmpty &&
              currentRow.any((f) => f.trim().isNotEmpty)) {
            rows.add(currentRow);
          }
          currentRow = <String>[];
        } else if (c == '\r') {
          // skip carriage return
        } else {
          currentField.write(c);
        }
      }
    }

    // Flush last field/row
    if (currentField.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentField.toString());
      if (currentRow.any((f) => f.trim().isNotEmpty)) {
        rows.add(currentRow);
      }
    }

    if (rows.isEmpty) return;

    // First row is header: Id, en, es, fr, de, ...
    final header = rows[0];
    if (header.isEmpty || header[0].trim().toLowerCase() != 'id') return;

    // Extract locale codes from columns 1+
    for (var col = 1; col < header.length; col++) {
      final locale = header[col].trim();
      if (locale.isNotEmpty) {
        _supportedLocales.add(locale);
        _data[locale] = {};
      }
    }

    // Parse data rows
    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      final key = row[0].trim();
      if (key.isEmpty) continue;

      for (var col = 1; col < row.length && col <= _supportedLocales.length; col++) {
        final locale = _supportedLocales[col - 1];
        final text = row[col].trim();
        if (text.isNotEmpty) {
          _data[locale]![key] = text;
        }
      }
    }
  }

  /// Get localized text for a key, with optional variable injection.
  ///
  /// Falls back to English if the key is missing in the current locale.
  /// Falls back to the key itself if missing in all locales.
  ///
  /// Variable injection uses `{0}`, `{1}`, etc. placeholders:
  /// ```dart
  /// L.tr('round_number', [5, 10]) // "Round 5 of 10"
  /// ```
  String getText(String key, [List<dynamic>? args]) {
    // Try current locale first
    var text = _data[_currentLocale]?[key];

    // Fall back to English
    if (text == null && _currentLocale != 'en') {
      text = _data['en']?[key];
    }

    // Fall back to key itself, converting underscore_keys to readable text
    // e.g., 'wallet_info_save_fees_title' → 'Wallet Info Save Fees Title'
    //        'create_event' → 'Create Event'
    if (text == null) {
      if (key.contains('_')) {
        // Strip common prefixes that are just namespacing
        var readable = key;
        for (final prefix in [
          'admin_', 'auth_', 'cash_recon_', 'cash_sale_', 'create_',
          'common_', 'events_home_', 'favor_ticket_', 'nfc_transfer_',
          'nft_ticket_', 'payments_', 'profile_', 'promo_', 'receive_ticket_',
          'referral_', 'resale_', 'seat_picker_', 'seller_', 'settings_',
          'staff_', 'subscription_', 'wallet_', 'waitlist_', 'widget_',
        ]) {
          if (readable.startsWith(prefix)) {
            readable = readable.substring(prefix.length);
            break;
          }
        }
        // Convert underscores to spaces and capitalize each word
        text = readable
            .split('_')
            .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
      } else {
        text = key;
      }
    }

    // Variable injection
    if (args != null && args.isNotEmpty) {
      for (var i = 0; i < args.length; i++) {
        text = text!.replaceAll('{$i}', args[i].toString());
      }
    }

    return text!;
  }

  /// Set the active locale and persist preference.
  Future<void> setLocale(String locale) async {
    if (!_data.containsKey(locale)) return;
    _currentLocale = locale;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale);
  }
}

/// Static API for global localization access.
///
/// Usage:
/// ```dart
/// // Simple lookup
/// L.tr('common_cancel')
///
/// // With variable injection
/// L.tr('event_tickets_remaining', [42])
///
/// // In widgets (must watch localeProvider for rebuilds):
/// ref.watch(localeProvider);
/// Text(L.tr('auth_login_title'))
/// ```
class L {
  static final _service = LocalizationService();

  /// Initialize localization — call once at app startup.
  static Future<void> init() => _service.loadFromAsset();

  /// Get localized text for a key, with optional `{0}` `{1}` variable injection.
  static String tr(String key, [List<dynamic>? args]) =>
      _service.getText(key, args);

  /// Set the active locale (persisted to SharedPreferences).
  static Future<void> setLocale(String locale) => _service.setLocale(locale);

  /// Current locale code (e.g. 'en', 'es', 'ja').
  static String get locale => _service.currentLocale;

  /// All supported locale codes parsed from the CSV header.
  static List<String> get supportedLocales => _service.supportedLocales;

  /// Human-readable display info for each supported locale.
  static final Map<String, ({String name, String nativeName})> localeNames = {
    'en': (name: 'English', nativeName: 'English'),
    'es': (name: 'Spanish', nativeName: 'Espanol'),
    'fr': (name: 'French', nativeName: 'Francais'),
    'de': (name: 'German', nativeName: 'Deutsch'),
    'pt': (name: 'Portuguese', nativeName: 'Portugues'),
    'it': (name: 'Italian', nativeName: 'Italiano'),
    'nl': (name: 'Dutch', nativeName: 'Nederlands'),
    'ru': (name: 'Russian', nativeName: 'Russkij'),
    'ja': (name: 'Japanese', nativeName: '\u65E5\u672C\u8A9E'),
    'ko': (name: 'Korean', nativeName: '\uD55C\uAD6D\uC5B4'),
    'zh': (name: 'Chinese (Simplified)', nativeName: '\u7B80\u4F53\u4E2D\u6587'),
    'zh_TW': (name: 'Chinese (Traditional)', nativeName: '\u7E41\u9AD4\u4E2D\u6587'),
    'ar': (name: 'Arabic', nativeName: '\u0627\u0644\u0639\u0631\u0628\u064A\u0629'),
    'hi': (name: 'Hindi', nativeName: '\u0939\u093F\u0928\u094D\u0926\u0940'),
    'tr': (name: 'Turkish', nativeName: 'Turkce'),
    'pl': (name: 'Polish', nativeName: 'Polski'),
    'th': (name: 'Thai', nativeName: '\u0E44\u0E17\u0E22'),
    'id': (name: 'Indonesian', nativeName: 'Bahasa Indonesia'),
  };
}
