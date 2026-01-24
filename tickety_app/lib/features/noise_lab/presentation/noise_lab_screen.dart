import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/graphics/graphics.dart';

/// A screen where users can generate custom noise textures interactively.
class NoiseLabScreen extends StatefulWidget {
  const NoiseLabScreen({super.key});

  @override
  State<NoiseLabScreen> createState() => _NoiseLabScreenState();
}

class _NoiseLabScreenState extends State<NoiseLabScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _canvasKey = GlobalKey();
  final Random _random = Random();

  Timer? _animationTimer;
  bool _isGenerating = false;
  bool _showSaveButton = false;
  double _timeOffset = 0;
  int _currentSeed = 0;

  // Color transition state
  double _colorProgress = 0; // 0 to 1 progress between color schemes
  int _fromColorIndex = 0;
  int _toColorIndex = 1;

  // Predefined color schemes for smooth cycling
  static const List<List<Color>> _colorSchemes = [
    [Color(0xFFFF6B6B), Color(0xFF4ECDC4), Color(0xFF45B7D1), Color(0xFFDDA0DD)],
    [Color(0xFFf093fb), Color(0xFFf5576c), Color(0xFFffecd2)],
    [Color(0xFF0077B6), Color(0xFF00B4D8), Color(0xFF90E0EF), Color(0xFFCAF0F8)],
    [Color(0xFF667eea), Color(0xFF764ba2), Color(0xFFf093fb)],
    [Color(0xFFFFE66D), Color(0xFFFF6B6B), Color(0xFF4ECDC4)],
    [Color(0xFF2C3E50), Color(0xFF3498DB), Color(0xFF1ABC9C)],
    [Color(0xFFE74C3C), Color(0xFFF39C12), Color(0xFFF1C40F)],
    [Color(0xFF8E44AD), Color(0xFF3498DB), Color(0xFF1ABC9C), Color(0xFFE74C3C)],
  ];

  @override
  void initState() {
    super.initState();
    _currentSeed = _random.nextInt(10000);
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  /// Interpolate between two color lists
  List<Color> _lerpColors(List<Color> from, List<Color> to, double t) {
    final maxLen = max(from.length, to.length);
    final result = <Color>[];
    for (var i = 0; i < maxLen; i++) {
      final fromColor = from[i % from.length];
      final toColor = to[i % to.length];
      result.add(Color.lerp(fromColor, toColor, t)!);
    }
    return result;
  }

  List<Color> get _currentColors {
    final from = _colorSchemes[_fromColorIndex % _colorSchemes.length];
    final to = _colorSchemes[_toColorIndex % _colorSchemes.length];
    return _lerpColors(from, to, _colorProgress);
  }

  void _startGenerating() {
    setState(() {
      _isGenerating = true;
      _showSaveButton = false;
    });

    HapticFeedback.lightImpact();

    // Smooth calming animation
    _animationTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      setState(() {
        // Smooth scroll - visible but calming
        _timeOffset += 0.25;

        // Smooth color transition
        _colorProgress += 0.003; // ~10 seconds per full transition
        if (_colorProgress >= 1.0) {
          _colorProgress = 0;
          _fromColorIndex = _toColorIndex;
          _toColorIndex = (_toColorIndex + 1) % _colorSchemes.length;
        }
      });
    });
  }

  void _stopGenerating() {
    _animationTimer?.cancel();
    HapticFeedback.mediumImpact();

    setState(() {
      _isGenerating = false;
      _showSaveButton = true;
    });
  }

  Future<void> _saveImage() async {
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();

      // For now, show success - full file saving would require platform-specific code
      // The bytes are ready if we want to implement file_picker or share_plus later
      debugPrint('Generated noise image: ${bytes.length} bytes');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Image ready! Use screenshot to save.'),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _currentColors.first,
          ),
        );
      }

      setState(() => _showSaveButton = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final canvasSize = min(size.width - 64, size.height * 0.5);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Make Some Noise'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Instructions
            AnimatedOpacity(
              opacity: _isGenerating ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _showSaveButton
                      ? 'Nice! Tap the save icon or screenshot to keep it.'
                      : 'Press and hold to generate',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Canvas
            Center(
              child: GestureDetector(
                onLongPressStart: (_) => _startGenerating(),
                onLongPressEnd: (_) => _stopGenerating(),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Noise canvas
                    RepaintBoundary(
                      key: _canvasKey,
                      child: Container(
                        width: canvasSize,
                        height: canvasSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _currentColors.first
                                  .withValues(alpha: 0.3),
                              blurRadius: 32,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: CustomPaint(
                            size: Size(canvasSize, canvasSize),
                            painter: _NoisePainter(
                              colors: _currentColors,
                              timeOffset: _timeOffset,
                              seed: _currentSeed,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Hold indicator
                    if (!_isGenerating && !_showSaveButton)
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.3),
                        ),
                        child: const Icon(
                          Icons.touch_app,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    // Generating indicator
                    if (_isGenerating)
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 3,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.waves,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Save button
            AnimatedOpacity(
              opacity: _showSaveButton ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: AnimatedScale(
                scale: _showSaveButton ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 200),
                child: IconButton.filled(
                  onPressed: _showSaveButton ? _saveImage : null,
                  icon: const Icon(Icons.save_alt),
                  iconSize: 28,
                  style: IconButton.styleFrom(
                    backgroundColor: _currentColors.first,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  final List<Color> colors;
  final double timeOffset;
  final int seed;

  _NoisePainter({
    required this.colors,
    required this.timeOffset,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final config = NoiseConfig(
      colors: colors,
      seed: seed,
      scale: 0.012,      // More detailed, pronounced patterns
      octaves: 3,        // Fewer layers = clearer shapes
      persistence: 0.7,  // Higher contrast between colors
    );
    final generator = NoiseGenerator(config: config);
    final paint = Paint();

    // Very slowly rotating direction angle (full rotation every ~5 minutes)
    final angle = timeOffset * 0.004;
    final dirX = cos(angle);
    final dirY = sin(angle);

    // Smooth pixels
    const pixelSize = 3.0;
    final cols = (size.width / pixelSize).ceil();
    final rows = (size.height / pixelSize).ceil();

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        // Flow direction slowly rotates over time
        final color = generator.getColorAt(
          x + timeOffset * dirX,
          y + timeOffset * dirY,
        );
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
  bool shouldRepaint(_NoisePainter oldDelegate) =>
      oldDelegate.timeOffset != timeOffset ||
      oldDelegate.colors != colors ||
      oldDelegate.seed != seed;
}
