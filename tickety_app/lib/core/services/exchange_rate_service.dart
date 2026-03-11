import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Fetches and caches exchange rates from the Frankfurter API (ECB data).
/// Free, no API key, updated daily.
class ExchangeRateService {
  ExchangeRateService._();
  static final instance = ExchangeRateService._();

  static const _baseUrl = 'https://api.frankfurter.app';
  static const _cacheKey = 'exchange_rates_cache';
  static const _cacheTimeKey = 'exchange_rates_cached_at';
  static const _staleDuration = Duration(hours: 12);

  /// Rates keyed by currency code, relative to USD.
  /// e.g. {'eur': 0.923, 'gbp': 0.789, 'cad': 1.359, 'aud': 1.527, 'usd': 1.0}
  Map<String, double> _rates = {'usd': 1.0};
  bool _loaded = false;

  Map<String, double> get rates => _rates;
  bool get isLoaded => _loaded;

  /// Load rates — tries cache first, fetches from API if stale.
  Future<void> loadRates() async {
    final prefs = await SharedPreferences.getInstance();

    // Try cache first
    final cachedJson = prefs.getString(_cacheKey);
    final cachedAtMs = prefs.getInt(_cacheTimeKey) ?? 0;
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
    final isStale = DateTime.now().difference(cachedAt) > _staleDuration;

    if (cachedJson != null) {
      _rates = _parseCache(cachedJson);
      _loaded = true;
    }

    // Fetch fresh if stale or no cache
    if (isStale || cachedJson == null) {
      try {
        await _fetchFromApi(prefs);
      } catch (_) {
        // Keep cached rates on network failure
      }
    }
  }

  /// Force refresh rates from the API.
  Future<void> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    await _fetchFromApi(prefs);
  }

  /// Convert an amount in cents from one currency to another.
  /// Returns the converted amount in cents.
  int convert(int cents, {required String from, required String to}) {
    if (from == to) return cents;
    final fromRate = _rates[from.toLowerCase()] ?? 1.0;
    final toRate = _rates[to.toLowerCase()] ?? 1.0;
    // Convert: cents_in_from → USD → cents_in_to
    return (cents / fromRate * toRate).round();
  }

  /// Get the exchange rate from one currency to another.
  double getRate({required String from, required String to}) {
    if (from == to) return 1.0;
    final fromRate = _rates[from.toLowerCase()] ?? 1.0;
    final toRate = _rates[to.toLowerCase()] ?? 1.0;
    return toRate / fromRate;
  }

  Future<void> _fetchFromApi(SharedPreferences prefs) async {
    // Frankfurter uses EUR as base. We fetch EUR→others, then rebase to USD.
    final uri = Uri.parse('$_baseUrl/latest?from=USD&to=EUR,GBP,CAD,AUD');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final apiRates = data['rates'] as Map<String, dynamic>?;
    if (apiRates == null) return;

    // Build USD-based rate map
    final newRates = <String, double>{'usd': 1.0};
    for (final entry in apiRates.entries) {
      newRates[entry.key.toLowerCase()] = (entry.value as num).toDouble();
    }

    _rates = newRates;
    _loaded = true;

    // Cache
    await prefs.setString(_cacheKey, jsonEncode(newRates));
    await prefs.setInt(
        _cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  Map<String, double> _parseCache(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final result = <String, double>{'usd': 1.0};
    for (final entry in decoded.entries) {
      result[entry.key] = (entry.value as num).toDouble();
    }
    return result;
  }
}
