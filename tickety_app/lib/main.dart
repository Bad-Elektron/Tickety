import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/config.dart';
import 'core/debug/debug.dart';
import 'core/errors/errors.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/services.dart';
import 'core/state/state.dart';
import 'features/events/presentation/events_home_screen.dart';

Future<void> main() async {
  // Initialize error handling first
  ErrorHandler.init();

  // Run app in guarded zone to catch async errors
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    AppLogger.info('Starting Tickety app', tag: 'Main');

    // Initialize environment configuration
    await EnvConfig.initialize();
    AppLogger.info('Environment config loaded', tag: 'Main');

    // Initialize Supabase client
    await SupabaseService.initialize();
    AppLogger.info('Supabase initialized', tag: 'Main');

    // Initialize Stripe for payments (non-blocking - app works without it)
    try {
      await StripeService.initialize();
      AppLogger.info('Stripe initialized', tag: 'Main');
    } catch (e, stack) {
      AppLogger.error(
        'Failed to initialize Stripe - payments will be unavailable',
        error: e,
        stackTrace: stack,
        tag: 'Main',
      );
    }

    // Initialize notification service (non-blocking - app works without it)
    try {
      await NotificationService.initialize();
      AppLogger.info('Notification service initialized', tag: 'Main');
    } catch (e, stack) {
      AppLogger.error(
        'Failed to initialize notification service - local notifications will be unavailable',
        error: e,
        stackTrace: stack,
        tag: 'Main',
      );
    }

    // Wrap with ProviderScope for Riverpod state management
    runApp(const ProviderScope(child: TicketyApp()));
  }, (error, stack) {
    AppLogger.error(
      'Uncaught error in root zone',
      error: error,
      stackTrace: stack,
      tag: 'Main',
    );
  });
}

/// Custom scroll behavior that enables mouse drag scrolling.
///
/// By default, Flutter web/desktop only allows touch drag scrolling.
/// This enables drag scrolling for all pointer devices (mouse, touch, stylus).
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

/// The root widget for the Tickety application.
class TicketyApp extends ConsumerStatefulWidget {
  const TicketyApp({super.key});

  @override
  ConsumerState<TicketyApp> createState() => _TicketyAppState();
}

class _TicketyAppState extends ConsumerState<TicketyApp> {
  final _appState = AppState();

  @override
  void initState() {
    super.initState();
    _appState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _appState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Watch theme mode from Riverpod provider
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Tickety',
      debugShowCheckedModeBanner: false,
      // Navigator key for debug menu access from outside Navigator tree
      navigatorKey: debugNavigatorKey,
      // Enable mouse drag scrolling
      scrollBehavior: AppScrollBehavior(),
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: themeMode,
      builder: (context, child) {
        return DebugOverlay(
          enabled: _appState.debugMode,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const EventsHomeScreen(),
    );
  }

  static ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
    );
  }

  static ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
    );
  }
}
