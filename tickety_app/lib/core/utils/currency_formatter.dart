import '../services/exchange_rate_service.dart';

/// Supported currencies with their display properties.
enum AppCurrency {
  usd('usd', 'USD', '\$', 'US Dollar'),
  eur('eur', 'EUR', '\u20AC', 'Euro'),
  gbp('gbp', 'GBP', '\u00A3', 'British Pound'),
  cad('cad', 'CAD', 'CA\$', 'Canadian Dollar'),
  aud('aud', 'AUD', 'A\$', 'Australian Dollar');

  const AppCurrency(this.code, this.displayCode, this.symbol, this.name);

  final String code;
  final String displayCode;
  final String symbol;
  final String name;

  static AppCurrency fromCode(String code) {
    return AppCurrency.values.firstWhere(
      (c) => c.code == code.toLowerCase(),
      orElse: () => AppCurrency.usd,
    );
  }
}

/// Formats cent amounts according to the given currency,
/// with optional live conversion via exchange rates.
class CurrencyFormatter {
  const CurrencyFormatter._();

  /// Format cents to a currency string (e.g., "$12.34", "€12.34").
  /// No conversion — just formats the raw amount with the currency symbol.
  static String format(int cents, {String currencyCode = 'usd'}) {
    final currency = AppCurrency.fromCode(currencyCode);
    final amount = (cents / 100).toStringAsFixed(2);
    return '${currency.symbol}$amount';
  }

  /// Format cents with the currency code suffix (e.g., "$12.34 USD").
  static String formatWithCode(int cents, {String currencyCode = 'usd'}) {
    final currency = AppCurrency.fromCode(currencyCode);
    final amount = (cents / 100).toStringAsFixed(2);
    return '${currency.symbol}$amount ${currency.displayCode}';
  }

  /// Convert cents from [fromCurrency] and format in [toCurrency].
  /// Uses live exchange rates. Falls back to raw format if rates unavailable.
  /// Example: convertAndFormat(5000, from: 'usd', to: 'eur') → "€46.15"
  static String convertAndFormat(
    int cents, {
    required String fromCurrency,
    required String toCurrency,
  }) {
    if (fromCurrency == toCurrency) {
      return format(cents, currencyCode: toCurrency);
    }

    final service = ExchangeRateService.instance;
    if (!service.isLoaded) {
      return format(cents, currencyCode: fromCurrency);
    }

    final converted = service.convert(cents, from: fromCurrency, to: toCurrency);
    return format(converted, currencyCode: toCurrency);
  }

  /// Convert cents from [fromCurrency] to [toCurrency] and return the
  /// formatted string with an approximate indicator when converted.
  /// Example: displayAmount(5000, from: 'usd', display: 'eur') → "~€46.15"
  static String displayAmount(
    int cents, {
    required String fromCurrency,
    required String displayCurrency,
  }) {
    if (fromCurrency == displayCurrency) {
      return format(cents, currencyCode: displayCurrency);
    }

    final service = ExchangeRateService.instance;
    if (!service.isLoaded) {
      // No rates yet — show original with code
      return formatWithCode(cents, currencyCode: fromCurrency);
    }

    final converted = service.convert(cents, from: fromCurrency, to: displayCurrency);
    return '~${format(converted, currencyCode: displayCurrency)}';
  }
}
