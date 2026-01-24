import 'package:flutter/foundation.dart';

/// Account tier levels.
enum AccountTier {
  base(label: 'Base', color: 0xFF6B7280),
  pro(label: 'Pro', color: 0xFF8B5CF6),
  enterprise(label: 'Enterprise', color: 0xFFEAB308);

  const AccountTier({
    required this.label,
    required this.color,
  });

  final String label;
  final int color;
}

/// Global application state for debug settings and account tier.
///
/// Uses ChangeNotifier for reactive updates across the app.
class AppState extends ChangeNotifier {
  static final AppState _instance = AppState._internal();

  factory AppState() => _instance;

  AppState._internal();

  /// Current account tier.
  AccountTier _tier = AccountTier.base;
  AccountTier get tier => _tier;
  set tier(AccountTier value) {
    if (_tier != value) {
      _tier = value;
      notifyListeners();
    }
  }

  /// Whether debug mode is enabled (shows FPS overlay).
  bool _debugMode = false;
  bool get debugMode => _debugMode;
  set debugMode(bool value) {
    if (_debugMode != value) {
      _debugMode = value;
      notifyListeners();
    }
  }

  /// Toggle debug mode.
  void toggleDebugMode() {
    debugMode = !debugMode;
  }

  /// Cycle through tiers.
  void cycleTier() {
    final index = AccountTier.values.indexOf(_tier);
    tier = AccountTier.values[(index + 1) % AccountTier.values.length];
  }
}
