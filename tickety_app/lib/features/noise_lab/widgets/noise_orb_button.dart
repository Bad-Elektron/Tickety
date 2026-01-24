import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/graphics/graphics.dart';
import '../presentation/noise_lab_screen.dart';

/// A circular button with animated noise texture that navigates to NoiseLabScreen.
///
/// The noise texture refreshes when the app is reopened after [refreshInterval].
class NoiseOrbButton extends StatefulWidget {
  /// How long before the noise texture refreshes on app reopen.
  final Duration refreshInterval;

  /// Size of the orb button.
  final double size;

  const NoiseOrbButton({
    super.key,
    this.refreshInterval = const Duration(hours: 1),
    this.size = 48,
  });

  @override
  State<NoiseOrbButton> createState() => _NoiseOrbButtonState();
}

class _NoiseOrbButtonState extends State<NoiseOrbButton> {
  static const _prefsKey = 'noise_orb_last_refresh';
  static const _prefsSeedKey = 'noise_orb_seed';

  NoiseConfig? _config;
  int _currentPresetIndex = 0;

  // Pool of 10 preset configurations
  static final List<NoiseConfig Function(int seed)> _presets = [
    (seed) => NoisePresets.vibrantEvents(seed),
    (seed) => NoisePresets.sunset(seed),
    (seed) => NoisePresets.ocean(seed),
    (seed) => NoisePresets.subtle(seed),
    (seed) => NoisePresets.darkMood(seed),
    (seed) => NoiseConfig(
          colors: const [Color(0xFFFFE66D), Color(0xFFFF6B6B), Color(0xFF4ECDC4)],
          seed: seed,
          scale: 0.007,
          octaves: 4,
          persistence: 0.55,
        ),
    (seed) => NoiseConfig(
          colors: const [Color(0xFF2C3E50), Color(0xFF3498DB), Color(0xFF1ABC9C)],
          seed: seed,
          scale: 0.008,
          octaves: 3,
          persistence: 0.5,
        ),
    (seed) => NoiseConfig(
          colors: const [Color(0xFFE74C3C), Color(0xFFF39C12), Color(0xFFF1C40F)],
          seed: seed,
          scale: 0.006,
          octaves: 4,
          persistence: 0.6,
        ),
    (seed) => NoiseConfig(
          colors: const [Color(0xFF8E44AD), Color(0xFF3498DB), Color(0xFF1ABC9C)],
          seed: seed,
          scale: 0.009,
          octaves: 5,
          persistence: 0.5,
        ),
    (seed) => NoiseConfig(
          colors: const [Color(0xFFFC466B), Color(0xFF3F5EFB)],
          seed: seed,
          scale: 0.005,
          octaves: 3,
          persistence: 0.45,
        ),
  ];

  @override
  void initState() {
    super.initState();
    _initializeConfig();
  }

  Future<void> _initializeConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRefresh = prefs.getInt(_prefsKey) ?? 0;
    final savedSeed = prefs.getInt(_prefsSeedKey) ?? Random().nextInt(10000);
    final now = DateTime.now().millisecondsSinceEpoch;

    // Check if we should refresh
    if (now - lastRefresh > widget.refreshInterval.inMilliseconds) {
      // Time to refresh - pick new random preset and seed
      final random = Random();
      _currentPresetIndex = random.nextInt(_presets.length);
      final newSeed = random.nextInt(10000);

      await prefs.setInt(_prefsKey, now);
      await prefs.setInt(_prefsSeedKey, newSeed);

      setState(() {
        _config = _presets[_currentPresetIndex](newSeed);
      });
    } else {
      // Use saved configuration
      _currentPresetIndex = (savedSeed % _presets.length);
      setState(() {
        _config = _presets[_currentPresetIndex](savedSeed);
      });
    }
  }

  void _navigateToNoiseLab() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NoiseLabScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;

    // Show loading placeholder while config initializes
    if (config == null) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      );
    }

    return GestureDetector(
      onTap: _navigateToNoiseLab,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: config.colors.first.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _NoiseOrbPainter(config: config),
          ),
        ),
      ),
    );
  }
}

class _NoiseOrbPainter extends CustomPainter {
  final NoiseConfig config;

  _NoiseOrbPainter({required this.config});

  @override
  void paint(Canvas canvas, Size size) {
    final generator = NoiseGenerator(config: config);
    final paint = Paint();

    // Use larger pixels for small button size
    const pixelSize = 3.0;
    final cols = (size.width / pixelSize).ceil();
    final rows = (size.height / pixelSize).ceil();

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final color = generator.getColorAt(x.toDouble(), y.toDouble());
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(
            x * pixelSize,
            y * pixelSize,
            pixelSize,
            pixelSize,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NoiseOrbPainter oldDelegate) =>
      oldDelegate.config != config;
}
