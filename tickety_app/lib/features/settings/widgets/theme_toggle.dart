import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An animated sun/moon toggle for switching between light and dark themes.
class ThemeToggle extends StatefulWidget {
  const ThemeToggle({
    super.key,
    required this.isDarkMode,
    required this.onToggle,
    this.size = 60,
  });

  final bool isDarkMode;
  final VoidCallback onToggle;
  final double size;

  @override
  State<ThemeToggle> createState() => _ThemeToggleState();
}

class _ThemeToggleState extends State<ThemeToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    ));

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0.8)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.8, end: 1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
    ]).animate(_controller);

    if (widget.isDarkMode) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(ThemeToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDarkMode != widget.isDarkMode) {
      if (widget.isDarkMode) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onToggle,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(
                      const Color(0xFFFFF3E0),
                      const Color(0xFF1A237E),
                      _rotationAnimation.value,
                    )!,
                    Color.lerp(
                      const Color(0xFFFFE0B2),
                      const Color(0xFF311B92),
                      _rotationAnimation.value,
                    )!,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color.lerp(
                      const Color(0xFFFFB74D).withValues(alpha: 0.4),
                      const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                      _rotationAnimation.value,
                    )!,
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Sun
                  Opacity(
                    opacity: 1 - _rotationAnimation.value,
                    child: Transform.rotate(
                      angle: _rotationAnimation.value * math.pi,
                      child: _SunIcon(size: widget.size * 0.5),
                    ),
                  ),
                  // Moon
                  Opacity(
                    opacity: _rotationAnimation.value,
                    child: Transform.rotate(
                      angle: (1 - _rotationAnimation.value) * -math.pi,
                      child: _MoonIcon(size: widget.size * 0.45),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SunIcon extends StatelessWidget {
  const _SunIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SunPainter(),
    );
  }
}

class _SunPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.25;

    // Sun body
    final bodyPaint = Paint()
      ..color = const Color(0xFFFF9800)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, bodyPaint);

    // Sun rays
    final rayPaint = Paint()
      ..color = const Color(0xFFFF9800)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round;

    const rayCount = 8;
    final rayLength = size.width * 0.15;
    final rayStart = radius + size.width * 0.08;

    for (var i = 0; i < rayCount; i++) {
      final angle = (i * 2 * math.pi / rayCount) - math.pi / 2;
      final start = Offset(
        center.dx + rayStart * math.cos(angle),
        center.dy + rayStart * math.sin(angle),
      );
      final end = Offset(
        center.dx + (rayStart + rayLength) * math.cos(angle),
        center.dy + (rayStart + rayLength) * math.sin(angle),
      );
      canvas.drawLine(start, end, rayPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MoonIcon extends StatelessWidget {
  const _MoonIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MoonPainter(),
    );
  }
}

class _MoonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;

    // Moon body (crescent)
    final moonPaint = Paint()
      ..color = const Color(0xFFF5F5F5)
      ..style = PaintingStyle.fill;

    // Draw full circle
    canvas.drawCircle(center, radius, moonPaint);

    // Cut out crescent with darker circle
    final cutoutPaint = Paint()
      ..color = const Color(0xFF1A237E)
      ..style = PaintingStyle.fill;

    final cutoutOffset = Offset(
      center.dx + radius * 0.4,
      center.dy - radius * 0.2,
    );
    canvas.drawCircle(cutoutOffset, radius * 0.75, cutoutPaint);

    // Add stars
    final starPaint = Paint()
      ..color = const Color(0xFFF5F5F5).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    // Small decorative stars
    canvas.drawCircle(
      Offset(center.dx + radius * 0.8, center.dy - radius * 0.6),
      size.width * 0.03,
      starPaint,
    );
    canvas.drawCircle(
      Offset(center.dx + radius * 0.5, center.dy + radius * 0.7),
      size.width * 0.02,
      starPaint,
    );
    canvas.drawCircle(
      Offset(center.dx - radius * 0.7, center.dy - radius * 0.4),
      size.width * 0.025,
      starPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
