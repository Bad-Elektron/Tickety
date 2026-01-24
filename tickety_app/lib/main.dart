import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/config.dart';
import 'core/debug/debug.dart';
import 'core/services/services.dart';
import 'core/state/state.dart';
import 'features/events/presentation/events_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize environment configuration
  await EnvConfig.initialize();

  // Initialize Supabase client
  await SupabaseService.initialize();

  // Wrap with ProviderScope for Riverpod state management
  runApp(const ProviderScope(child: TicketyApp()));
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
class TicketyApp extends StatefulWidget {
  const TicketyApp({super.key});

  @override
  State<TicketyApp> createState() => _TicketyAppState();
}

class _TicketyAppState extends State<TicketyApp> {
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
    return MaterialApp(
      title: 'Tickety',
      debugShowCheckedModeBanner: false,
      // Enable mouse drag scrolling
      scrollBehavior: AppScrollBehavior(),
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: ThemeMode.system,
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
