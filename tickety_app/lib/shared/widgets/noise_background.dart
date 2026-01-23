import 'package:flutter/material.dart';

import '../../core/graphics/graphics.dart';

/// A simple gradient background widget for event cards.
///
/// Uses gradients instead of procedural noise for maximum
/// performance during scrolling and animations.
class NoiseBackground extends StatelessWidget {
  /// Configuration for the noise/gradient colors.
  final NoiseConfig config;

  /// Optional child widget to display on top.
  final Widget? child;

  /// Resolution (unused, kept for API compatibility).
  final int resolution;

  /// Border radius for clipping.
  final BorderRadius? borderRadius;

  const NoiseBackground({
    super.key,
    required this.config,
    this.child,
    this.resolution = 6,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget background = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: config.colors,
        ),
        borderRadius: borderRadius,
      ),
      child: child,
    );

    if (borderRadius != null && child != null) {
      background = ClipRRect(
        borderRadius: borderRadius!,
        child: background,
      );
    }

    return RepaintBoundary(child: background);
  }
}

/// A simple gradient background for maximum performance.
class GradientBackground extends StatelessWidget {
  /// Colors for the gradient.
  final List<Color> colors;

  /// Optional child widget.
  final Widget? child;

  /// Gradient direction start.
  final AlignmentGeometry begin;

  /// Gradient direction end.
  final AlignmentGeometry end;

  /// Border radius for clipping.
  final BorderRadius? borderRadius;

  const GradientBackground({
    super.key,
    required this.colors,
    this.child,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: begin.resolve(TextDirection.ltr),
            end: end.resolve(TextDirection.ltr),
            colors: colors,
          ),
          borderRadius: borderRadius,
        ),
        child: child,
      ),
    );
  }
}
