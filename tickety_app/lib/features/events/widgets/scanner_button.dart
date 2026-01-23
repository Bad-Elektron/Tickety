import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A hold-to-scan button with fingerprint icon and animated progress.
///
/// When held for [holdDuration], triggers [onScanComplete].
/// Shows animated progress ring and pulsing effect while held.
/// Supports continuous scanning mode via [continuousMode].
class ScannerButton extends StatefulWidget {
  const ScannerButton({
    super.key,
    required this.onScanComplete,
    this.holdDuration = const Duration(seconds: 2),
    this.size = 100,
    this.continuousMode = false,
    this.onContinuousModeChanged,
  });

  /// Called when the button is held for the full duration.
  final VoidCallback onScanComplete;

  /// How long to hold before scan completes.
  final Duration holdDuration;

  /// Size of the button (thumb-sized by default).
  final double size;

  /// Whether continuous scanning mode is enabled.
  final bool continuousMode;

  /// Called when continuous mode toggle changes.
  final ValueChanged<bool>? onContinuousModeChanged;

  @override
  State<ScannerButton> createState() => _ScannerButtonState();
}

class _ScannerButtonState extends State<ScannerButton>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _pulseController;
  late AnimationController _continuousController;
  late Animation<double> _pulseAnimation;

  bool _isHolding = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    );

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onScanComplete();
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _continuousController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    if (widget.continuousMode) {
      _startContinuousMode();
    }
  }

  @override
  void didUpdateWidget(ScannerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.continuousMode != oldWidget.continuousMode) {
      if (widget.continuousMode) {
        _startContinuousMode();
      } else {
        _stopContinuousMode();
      }
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pulseController.dispose();
    _continuousController.dispose();
    super.dispose();
  }

  void _startContinuousMode() {
    setState(() => _isScanning = true);
    _continuousController.repeat();
    _pulseController.repeat(reverse: true);
  }

  void _stopContinuousMode() {
    setState(() => _isScanning = false);
    _continuousController.stop();
    _continuousController.reset();
    _pulseController.stop();
    _pulseController.reset();
  }

  void _onPressStart() {
    if (widget.continuousMode) return; // Ignore manual press in continuous mode

    setState(() {
      _isHolding = true;
      _isScanning = true;
    });
    _progressController.forward(from: 0);
    _pulseController.repeat(reverse: true);
    HapticFeedback.mediumImpact();
  }

  void _onPressEnd() {
    if (widget.continuousMode) return;
    if (!_isHolding) return;

    setState(() {
      _isHolding = false;
      _isScanning = false;
    });
    _progressController.stop();
    _progressController.reset();
    _pulseController.stop();
    _pulseController.reset();
  }

  void _onScanComplete() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isHolding = false;
      _isScanning = widget.continuousMode; // Stay scanning in continuous mode
    });
    if (!widget.continuousMode) {
      _pulseController.stop();
    }
    widget.onScanComplete();
  }

  void _onTapInContinuousMode() {
    if (!widget.continuousMode) return;
    HapticFeedback.heavyImpact();
    widget.onScanComplete();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Continuous mode toggle
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.loop,
                size: 18,
                color: widget.continuousMode
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Continuous',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: widget.continuousMode
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: widget.continuousMode
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 24,
                child: Switch(
                  value: widget.continuousMode,
                  onChanged: widget.onContinuousModeChanged,
                ),
              ),
            ],
          ),
        ),

        // Scanner button
        GestureDetector(
          onLongPressStart: (_) => _onPressStart(),
          onLongPressEnd: (_) => _onPressEnd(),
          onLongPressCancel: _onPressEnd,
          onTap: _onTapInContinuousMode,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _progressController,
              _pulseAnimation,
              _continuousController,
            ]),
            builder: (context, child) {
              final scale = _isScanning ? _pulseAnimation.value : 1.0;
              final progress = widget.continuousMode
                  ? _continuousController.value
                  : _progressController.value;

              return Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer glow when scanning
                      if (_isScanning)
                        Container(
                          width: widget.size + 16,
                          height: widget.size + 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withValues(alpha: 0.3),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                        ),

                      // Progress ring
                      CustomPaint(
                        size: Size(widget.size, widget.size),
                        painter: _ProgressRingPainter(
                          progress: progress,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          progressColor: colorScheme.primary,
                          strokeWidth: 5,
                          continuous: widget.continuousMode,
                        ),
                      ),

                      // Gradient circle background
                      Container(
                        width: widget.size - 18,
                        height: widget.size - 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colorScheme.primaryContainer,
                              colorScheme.primary.withValues(alpha: 0.7),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                              blurRadius: _isScanning ? 16 : 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.fingerprint,
                          size: widget.size * 0.45,
                          color: _isScanning
                              ? colorScheme.onPrimary
                              : colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            widget.continuousMode
                ? 'Tap to scan'
                : (_isScanning ? 'Scanning...' : 'Hold to scan'),
            key: ValueKey('${widget.continuousMode}_$_isScanning'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _isScanning
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              fontWeight: _isScanning ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;
  final bool continuous;

  _ProgressRingPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
    this.continuous = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background ring
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      if (continuous) {
        // Rotating arc for continuous mode
        final startAngle = 2 * math.pi * progress - math.pi / 2;
        const sweepAngle = math.pi * 0.75; // 3/4 of a circle

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          false,
          progressPaint,
        );
      } else {
        // Filling arc for hold mode
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -math.pi / 2,
          2 * math.pi * progress,
          false,
          progressPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.continuous != continuous;
  }
}
