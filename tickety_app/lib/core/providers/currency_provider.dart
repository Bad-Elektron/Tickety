import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/services.dart';
import '../utils/currency_formatter.dart';

const _prefKey = 'preferred_currency';

/// Notifier that manages the user's preferred currency and exchange rates.
///
/// Reads from local cache (SharedPreferences) first for instant display,
/// then syncs with the `profiles.preferred_currency` column in Supabase.
/// Also loads exchange rates from Frankfurter API (ECB data, free, no key).
class CurrencyNotifier extends StateNotifier<CurrencyState> {
  CurrencyNotifier() : super(const CurrencyState()) {
    _load();
  }

  Future<void> _load() async {
    // 1. Local cache first
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefKey);
    if (cached != null) {
      state = state.copyWith(currency: AppCurrency.fromCode(cached));
    }

    // 2. Load exchange rates (from cache, then API)
    await ExchangeRateService.instance.loadRates();
    state = state.copyWith(ratesLoaded: ExchangeRateService.instance.isLoaded);

    // 3. Sync from Supabase profile
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;

    try {
      final row = await SupabaseService.instance.client
          .from('profiles')
          .select('preferred_currency')
          .eq('id', user.id)
          .maybeSingle();

      if (row != null && row['preferred_currency'] != null) {
        final remote = AppCurrency.fromCode(row['preferred_currency'] as String);
        state = state.copyWith(currency: remote);
        await prefs.setString(_prefKey, remote.code);
      }
    } catch (_) {
      // Column may not exist yet on older DBs — keep local/default
    }
  }

  /// Change the user's preferred currency.
  Future<void> setCurrency(AppCurrency currency) async {
    if (state.currency == currency) return;
    state = state.copyWith(currency: currency);

    // Persist locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, currency.code);

    // Persist to Supabase
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;

    try {
      await SupabaseService.instance.client
          .from('profiles')
          .update({'preferred_currency': currency.code})
          .eq('id', user.id);
    } catch (_) {
      // Non-critical — local cache is authoritative for display
    }
  }

  /// Refresh exchange rates from the API.
  Future<void> refreshRates() async {
    await ExchangeRateService.instance.refresh();
    state = state.copyWith(ratesLoaded: ExchangeRateService.instance.isLoaded);
  }
}

/// Combined state: selected currency + whether rates are loaded.
class CurrencyState {
  final AppCurrency currency;
  final bool ratesLoaded;

  const CurrencyState({
    this.currency = AppCurrency.usd,
    this.ratesLoaded = false,
  });

  CurrencyState copyWith({AppCurrency? currency, bool? ratesLoaded}) {
    return CurrencyState(
      currency: currency ?? this.currency,
      ratesLoaded: ratesLoaded ?? this.ratesLoaded,
    );
  }
}

/// The user's currency state (currency + rates loaded flag).
final currencyStateProvider =
    StateNotifierProvider<CurrencyNotifier, CurrencyState>((ref) {
  return CurrencyNotifier();
});

/// The user's preferred currency enum.
final currencyProvider = Provider<AppCurrency>((ref) {
  return ref.watch(currencyStateProvider).currency;
});

/// Convenience: current currency code string (e.g., 'usd').
final currencyCodeProvider = Provider<String>((ref) {
  return ref.watch(currencyProvider).code;
});
