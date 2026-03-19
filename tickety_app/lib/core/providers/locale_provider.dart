import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/localization_service.dart';

/// Notifier that manages the current locale and triggers widget rebuilds.
///
/// Widgets that display localized text must call `ref.watch(localeProvider)`
/// to ensure they rebuild when the language changes.
class LocaleNotifier extends StateNotifier<String> {
  LocaleNotifier() : super(L.locale);

  /// Change the app language. Persists to SharedPreferences.
  Future<void> setLocale(String locale) async {
    await L.setLocale(locale);
    state = locale;
  }
}

/// Provider for the current locale. Watch this in any widget that uses [L.tr].
final localeProvider = StateNotifierProvider<LocaleNotifier, String>((ref) {
  return LocaleNotifier();
});
